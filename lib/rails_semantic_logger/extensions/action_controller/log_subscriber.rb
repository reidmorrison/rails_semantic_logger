ActionController::LogSubscriber

module ActionController
  class LogSubscriber
    # Sets procs to call when processing the controller action
    #
    # The procs will be given the event and the current log hash
    def self.extra_log_procs=(procs)
      @extra_log_procs = procs
    end

    # Procs to call when processing the controller action
    def self.extra_log_procs
      @extra_log_procs
    end

    # Log as debug to hide Processing messages in production
    def start_processing(event)
      controller_logger(event).debug { "Processing ##{event.payload[:action]}" }
    end

    def process_action(event)
      controller_logger(event).info do
        payload = event.payload
        params  = payload[:params].except(*INTERNAL_PARAMS)
        format  = payload[:format]
        format  = format.to_s.upcase if format.is_a?(Symbol)
        status  = payload[:status]

        if status.nil? && payload[:exception].present?
          exception_class_name = payload[:exception].first
          status               = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception_class_name)
        end

        log = {
          message:        "Completed ##{payload[:action]}",
          status:         status,
          status_message: Rack::Utils::HTTP_STATUS_CODES[status],
          format:         format,
          path:           payload[:path],
          action:         payload[:action],
          method:         payload[:method],
          duration:       event.duration
        }

        collect_runtimes(payload, log)
        log[:params] = params unless params.empty?

        self.class.extra_log_procs.each do |extra_log_proc|
          extra_log_proc.call(payload, log)
        end

        log
      end
    end

    def halted_callback(event)
      controller_logger(event).info { "Filter chain halted as #{event.payload[:filter].inspect} rendered or redirected" }
    end

    def send_file(event)
      controller_logger(event).info('Sent file') { {path: event.payload[:path], duration: event.duration} }
    end

    def redirect_to(event)
      controller_logger(event).info('Redirected to') { {location: event.payload[:location]} }
    end

    def send_data(event)
      controller_logger(event).info('Sent data') { {file_name: event.payload[:filename], duration: event.duration} }
    end

    def unpermitted_parameters(event)
      controller_logger(event).debug do
        unpermitted_keys = event.payload[:keys]
        "Unpermitted parameter#{'s' if unpermitted_keys.size > 1}: #{unpermitted_keys.join(", ")}"
      end
    end

    %w(write_fragment read_fragment exist_fragment?
       expire_fragment expire_page write_page).each do |method|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{method}(event)
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
      if controller = event.payload[:controller]
        begin
          controller.constantize.logger
        rescue NameError
          ActionController::Base.logger
        end
      else
        ActionController::Base.logger
      end
    end

    # Returns [Hash] runtimes for all registered runtime collection subscribers
    # For example, :view_runtime, :mongo_runtime, etc.
    def collect_runtimes(payload, log)
      payload.each_pair do |key, value|
        if match = key.to_s.match(/(.*)_runtime/)
          log[key] = value.to_f.round(2)
        end
      end
    end

  end
end
