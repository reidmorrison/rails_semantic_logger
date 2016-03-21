ActionController::LogSubscriber

module ActionController
  class LogSubscriber
    # Log as debug to hide Processing messages in production
    def start_processing(event)
      controller_logger(event).debug { "Processing ##{event.payload[:action]}" }
    end

    def process_action(event)
      controller_logger(event).info do
        payload = event.payload.dup
        payload[:params].except!(*INTERNAL_PARAMS)
        payload.delete(:params) if payload[:params].empty?

        format           = payload[:format]
        payload[:format] = format.to_s.upcase if format.is_a?(Symbol)

        exception = payload.delete(:exception)
        if payload[:status].nil? && exception.present?
          exception_class_name = exception.first
          payload[:status]     = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception_class_name)
        end

        # Rounds off the runtimes. For example, :view_runtime, :mongo_runtime, etc.
        payload.keys.each do |key|
          payload[key] = payload[key].to_f.round(2) if key.to_s.match(/(.*)_runtime/)
        end

        payload[:message]        = "Completed ##{payload[:action]}"
        payload[:status_message] = Rack::Utils::HTTP_STATUS_CODES[payload[:status]] if payload[:status].present?
        payload[:duration]       = event.duration
        payload
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

  end
end
