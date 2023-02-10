# Log actual exceptions, not a string representation
require "action_dispatch"

module ActionDispatch
  class DebugExceptions
    private

    undef_method :log_error
    def log_error(request, wrapper)
      return if !log_rescued_responses?(request) && wrapper.rescue_response?

      ActiveSupport::Deprecation.silence do
        ActionController::Base.logger.fatal(wrapper.exception)
      end
    end
  end
end
