# Log actual exceptions, not a string representation
require "action_dispatch"

module ActionDispatch
  class DebugExceptions
    private

    undef_method :log_error
    def log_error(request, wrapper)
      ActiveSupport::Deprecation.silence do
        level = wrapper.rescue_response? ? :debug : :fatal
        ActionController::Base.logger.log(level, wrapper.exception)
      end
    end
  end
end
