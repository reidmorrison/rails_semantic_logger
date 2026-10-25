# This subscriber is a reimplementation of Rails' own ActionController::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/actionpack/lib/action_controller/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/actionpack/lib/action_controller/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/actionpack/lib/action_controller/log_subscriber.rb
#
module RailsSemanticLogger
  module ActionController
    class LogSubscriber < ActiveSupport::LogSubscriber
      INTERNAL_PARAMS = %w[controller action format _method only_path].freeze

      class_attribute :backtrace_cleaner, default: ActiveSupport::BacktraceCleaner.new

      class << self
        attr_accessor :action_message_format, :processing_log_level
      end

      # Defaults to :debug so the Processing message is hidden in production. The engine raises it
      # to :info when `config.rails_semantic_logger.processing` is true.
      @processing_log_level = :debug

      def start_processing(event)
        controller_logger(event)&.send(self.class.processing_log_level) { action_message("Processing", event.payload) }
      end

      def process_action(event)
        controller_logger(event)&.info do
          # `event.payload` is shared with every other subscriber on this notification, so we work on
          # a copy. A shallow `dup` is sufficient: only mutate `payload` via top-level key reassignment
          # (e.g. `payload[:format] = ...`) or by writing into a freshly-created hash (e.g. the `.except`
          # result below). Never mutate a nested object that still belongs to the original payload
          # (e.g. `payload[:foo][:bar] = ...` on an unduped key), or the change will leak back into the
          # shared payload and corrupt what other subscribers see.
          payload = event.payload.dup

          # Unused, but needed for Devise 401 status code monkey patch to still work.
          ::ActionController::Base.log_process_action(payload)

          params = payload[:params]

          if params.is_a?(Hash) || params.is_a?(::ActionController::Parameters)
            # According to PR https://github.com/reidmorrison/rails_semantic_logger/pull/37/files
            # params is not always a Hash.
            payload[:params] = params.to_unsafe_h unless params.is_a?(Hash)
            payload[:params] = params.except(*INTERNAL_PARAMS)

            if payload[:params].empty?
              payload.delete(:params)
            elsif params["file"]
              # When logging to JSON the entire tempfile is logged, so convert it to a string.
              payload[:params]["file"] = params["file"].inspect
            end
          end

          format           = payload[:format]
          payload[:format] = format.to_s.upcase if format.is_a?(Symbol)

          payload[:path]   = extract_path(payload[:path]) if payload.key?(:path)

          exception = payload.delete(:exception)
          if payload[:status].nil? && exception.present?
            exception_class_name = exception.first
            payload[:status]     = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception_class_name)
          end

          # Rounds off the runtimes. For example, :view_runtime, :mongo_runtime, etc.
          payload.keys.each do |key|
            payload[key] = payload[key].to_f.round(2) if key.to_s =~ /(.*)_runtime/
          end

          payload[:allocations] = event.allocations
          payload[:cpu_time]    = event.cpu_time.round(2)
          payload[:idle_time]   = event.idle_time.round(2)
          payload[:gc_time]     = event.gc_time.round(2) if event.respond_to?(:gc_time)

          payload[:status_message] = ::Rack::Utils::HTTP_STATUS_CODES[payload[:status]] if payload[:status].present?

          payload.delete(:headers)
          payload.delete(:request)
          payload.delete(:response)

          {
            message:  action_message("Completed", event.payload),
            duration: event.duration,
            payload:  payload,
            metric:   "rails.controller.process_action"
          }
        end
      end

      def halted_callback(event)
        controller_logger(event)&.info do
          {
            message: "Filter chain halted as #{event.payload[:filter].inspect} rendered or redirected",
            metric:  "rails.controller.halted_callback"
          }
        end
      end

      # Rails 8.1+ emits this event when an exception is handled by a `rescue_from` callback.
      # On earlier Rails versions the event is never instrumented, so this handler is dormant.
      def rescue_from_callback(event)
        controller_logger(event)&.info do
          exception = event.payload[:exception]
          backtrace = exception.backtrace&.first
          backtrace = backtrace&.delete_prefix("#{Rails.root}/") if defined?(Rails.root) && Rails.root

          {
            message: "rescue_from handled #{exception.class}",
            payload: {
              exception:         exception.class.name,
              exception_message: exception.message,
              backtrace:         backtrace
            },
            metric:  "rails.controller.rescue_from_callback"
          }
        end
      end

      def send_file(event)
        controller_logger(event)&.info(message:  "Sent file",
                                       payload:  {path: event.payload[:path]},
                                       duration: event.duration,
                                       metric:   "rails.controller.send_file")
      end

      def redirect_to(event)
        payload = {location: event.payload[:location]}

        # Rails 8.1+ optionally logs the source location of the redirect when
        # ActionDispatch.verbose_redirect_logs is enabled.
        if ActionDispatch.respond_to?(:verbose_redirect_logs) && ActionDispatch.verbose_redirect_logs
          source           = redirect_source_location
          payload[:source] = source if source
        end

        controller_logger(event)&.info(message: "Redirected to", payload: payload,
                                       metric: "rails.controller.redirect_to")
      end

      # Rails 8.1+ emits this event for a redirect to another host when
      # `config.action_controller.action_on_open_redirect = :notify`. Rails' text subscriber never
      # logs it: on Rails 8.1 nothing subscribes to it, and on Rails 8.2 only its
      # StructuredEventSubscriber reports it, to `Rails.event`. So it is logged here at :warn, the
      # level Rails uses for `action_on_open_redirect = :log`.
      def open_redirect(event)
        controller_logger(event)&.warn do
          payload = event.payload
          request = payload[:request]

          {
            message:   "Open redirect detected",
            payload:   {
              location:       payload[:location],
              request_method: request&.method,
              request_path:   request&.path
            }.compact,
            backtrace: clean_backtrace(payload[:stack_trace]),
            metric:    "rails.controller.open_redirect"
          }
        end
      end

      # Rails 8.1+ emits this event for a path relative redirect, such as `redirect_to "foo"`, when
      # `config.action_controller.action_on_path_relative_redirect = :notify`. No Rails subscriber
      # logs it, so it is logged here at :warn, the level Rails uses for `:log`.
      def unsafe_redirect(event)
        controller_logger(event)&.warn do
          payload = event.payload

          {
            message:   payload[:message],
            payload:   {url: payload[:url]},
            backtrace: clean_backtrace(payload[:stack_trace]),
            metric:    "rails.controller.unsafe_redirect"
          }
        end
      end

      def send_data(event)
        controller_logger(event)&.info(message:  "Sent data",
                                       payload:  {file_name: event.payload[:filename]},
                                       duration: event.duration,
                                       metric:   "rails.controller.send_data")
      end

      def unpermitted_parameters(event)
        controller_logger(event)&.debug do
          unpermitted_keys = event.payload[:keys]
          payload          = {keys: unpermitted_keys}
          # Rails includes the controller/action context alongside the rejected keys.
          payload[:context] = event.payload[:context] if event.payload[:context]

          {
            message: "Unpermitted parameter#{'s' if unpermitted_keys.size > 1}: #{unpermitted_keys.join(', ')}",
            payload: payload
          }
        end
      end

      # Rails 8.2+ reports CSRF failures through these events instead of calling `logger.warn`
      # directly from RequestForgeryProtection. On earlier Rails versions the events are never
      # instrumented, so these handlers are dormant.
      def csrf_token_fallback(event)
        log_csrf_warning(__method__, event, "Falling back to CSRF token verification")
      end

      def csrf_request_blocked(event)
        log_csrf_warning(__method__, event, event.payload[:message])
      end

      def csrf_javascript_blocked(event)
        log_csrf_warning(__method__, event, event.payload[:message])
      end

      %w[write_fragment read_fragment exist_fragment?
         expire_fragment expire_page write_page].each do |method|
        class_eval <<-METHOD, __FILE__, __LINE__ + 1
          def #{method}(event)
            return unless ::ActionController::Base.enable_fragment_cache_logging
            controller_logger(event)&.info do
              key_or_path = event.payload[:key] || event.payload[:path]
              {message: "#{method.to_s.humanize} \#{key_or_path}", duration: event.duration, metric: "rails.controller.#{method.delete('?')}"}
            end
          end
        METHOD
      end

      private

      # Returns the logger of the controller that emitted the event, or ActionController::Base.logger
      # when the event names no controller or it cannot be found. Like Rails, which skips logging
      # when there is no logger, callers must allow for nil.
      def controller_logger(event)
        controller_class(event.payload)&.logger || ::ActionController::Base.logger
      end

      # Most events name their controller. The redirect events carry only the request, which knows
      # the controller handling it.
      def controller_class(payload)
        if payload[:controller]
          payload[:controller].constantize
        else
          payload[:request]&.controller_instance&.class
        end
      rescue NameError
        nil
      end

      # Removes framework and gem frames, leaving the application code that caused the event.
      def clean_backtrace(backtrace)
        backtrace_cleaner.clean(backtrace) if backtrace
      end

      # Rails logs every CSRF event at :warn, and only while log_warning_on_csrf_failure is on.
      def log_csrf_warning(event_name, event, message)
        return unless ::ActionController::Base.log_warning_on_csrf_failure

        controller_logger(event)&.warn do
          payload = event.payload
          {
            message: message,
            payload: {
              controller:     payload[:controller],
              action:         payload[:action],
              sec_fetch_site: payload[:sec_fetch_site]
            }.compact,
            metric:  "rails.controller.#{event_name}"
          }
        end
      end

      def extract_path(path)
        index = path.index("?")
        index ? path[0, index] : path
      end

      # Rails 8.1+ BacktraceCleaner exposes #first_clean_frame for verbose redirect logging.
      def redirect_source_location
        backtrace_cleaner.first_clean_frame if backtrace_cleaner.respond_to?(:first_clean_frame)
      end

      def action_message(message, payload)
        if self.class.action_message_format
          self.class.action_message_format.call(message, payload)
        else
          "#{message} ##{payload[:action]}"
        end
      end
    end
  end
end
