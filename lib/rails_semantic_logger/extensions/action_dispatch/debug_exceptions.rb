# Log actual exceptions, not a string representation
require "action_dispatch"

module ActionDispatch
  class DebugExceptions
    private

    undef_method :log_error
    if (Rails::VERSION::MAJOR == 7 && Rails::VERSION::MINOR >= 1) || Rails::VERSION::MAJOR > 7
      def log_error(_request, wrapper)
        Rails.application.deprecators.silence do
          level = wrapper.respond_to?(:rescue_response?) && wrapper.rescue_response? ? :debug : :fatal
          ActionController::Base.logger.log(level, wrapper.exception)
        end
      end
    else
      def log_error(_request, wrapper)
        ActiveSupport::Deprecation.silence do
          level = wrapper.respond_to?(:rescue_response?) && wrapper.rescue_response? ? :debug : :fatal
          ActionController::Base.logger.log(level, wrapper.exception)
        end
      end
    end
  end
end
