module RailsSemanticLogger
  module ActionController
    class LogSubscriber < ActiveSupport::LogSubscriber
      INTERNAL_PARAMS = %w[controller action format _method only_path].freeze

      # Log as debug to hide Processing messages in production
      def start_processing(event)
        controller_logger(event).debug { "Processing ##{event.payload[:action]}" }
      end

      def process_action(event)
        controller_logger(event).info do
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

          # Rails 6+ includes allocation count
          payload[:allocations] = event.allocations if event.respond_to?(:allocations)

          payload[:status_message] = ::Rack::Utils::HTTP_STATUS_CODES[payload[:status]] if payload[:status].present?

          # Causes excessive log output with Rails 5 RC1
          payload.delete(:headers)
          # Causes recursion in Rails 6.1.rc1
          payload.delete(:request)
          payload.delete(:response)

          {
            message:  "Completed ##{payload[:action]}",
            duration: event.duration,
            payload:  payload
          }
        end
      end

      def halted_callback(event)
        controller_logger(event).info { "Filter chain halted as #{event.payload[:filter].inspect} rendered or redirected" }
      end

      def send_file(event)
        controller_logger(event).info(message: "Sent file", payload: {path: event.payload[:path]}, duration: event.duration)
      end

      def redirect_to(event)
        controller_logger(event).info(message: "Redirected to", payload: {location: event.payload[:location]})
      end

      def send_data(event)
        controller_logger(event).info(message:  "Sent data",
                                      payload:  {file_name: event.payload[:filename]},
                                      duration: event.duration)
      end

      def unpermitted_parameters(event)
        controller_logger(event).debug do
          unpermitted_keys = event.payload[:keys]
          "Unpermitted parameter#{'s' if unpermitted_keys.size > 1}: #{unpermitted_keys.join(', ')}"
        end
      end

      %w[write_fragment read_fragment exist_fragment?
         expire_fragment expire_page write_page].each do |method|
        class_eval <<-METHOD, __FILE__, __LINE__ + 1
          def #{method}(event)
            # enable_fragment_cache_logging as of Rails 5
            return if ::ActionController::Base.respond_to?(:enable_fragment_cache_logging) && !::ActionController::Base.enable_fragment_cache_logging
            controller_logger(event).info do
              key_or_path = event.payload[:key] || event.payload[:path]
              {message: "#{method.to_s.humanize} \#{key_or_path}", duration: event.duration}
            end
          end
        METHOD
      end

      private

      # Returns the logger for the supplied event.
      # Returns ActionController::Base.logger if no controller is present
      def controller_logger(event)
        controller = event.payload[:controller]
        return ::ActionController::Base.logger unless controller

        controller.constantize.logger || ::ActionController::Base.logger
      rescue NameError
        ::ActionController::Base.logger
      end

      def extract_path(path)
        index = path.index("?")
        index ? path[0, index] : path
      end
    end
  end
end
