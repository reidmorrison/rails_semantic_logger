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
        ActionController::Base.logger.log(level, semantic_logger_exception(wrapper))
      end
    end

    # Returns the exception to log.
    #
    # When Rails' own log shows no backtrace for the exception, this is a copy of it without one.
    # Rails decides that in ExceptionWrapper#exception_trace: the exceptions in
    # ExceptionWrapper.silent_exceptions, such as a routing error raised in middleware, have no
    # backtrace once the request's backtrace cleaner has removed every frame outside the
    # application. The original exception is left unchanged, since Rails renders it and error
    # services report it.
    #
    # ExceptionWrapper only reads backtrace_locations, so it finds no frames at all in a backtrace
    # set from Strings, such as with `raise error, message, backtrace`. That exception keeps its
    # backtrace.
    def semantic_logger_exception(wrapper)
      exception = wrapper.exception
      # Rails wraps a SyntaxError in a proxy, which is not an Exception.
      exception = exception.__getobj__ if exception.is_a?(ActiveSupport::SyntaxErrorProxy)
      return exception unless exception.backtrace_locations && wrapper.exception_trace.empty?

      copy = exception.dup
      copy.set_backtrace([])
      copy
    end
  end
end
