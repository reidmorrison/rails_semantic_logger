# Log actual exceptions, not a string representation
require "action_dispatch"

module ActionDispatch
  class DebugExceptions
    private

    undef_method :log_error
    def log_error(request, wrapper)
      Rails.application.deprecators.silence do
        return if !log_rescued_responses?(request) && wrapper.rescue_response?

        level = request.get_header("action_dispatch.debug_exception_log_level")
        ActionController::Base.logger.log(level, wrapper.exception)
      end
    end
  end
end
