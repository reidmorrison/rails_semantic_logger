ActionController::LogSubscriber

module ActionController
  class LogSubscriber
    # Log as info to show Processing messages in production
    def start_processing(event)
      controller_logger(event).info { "Processing ##{event.payload[:action]}" }
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
