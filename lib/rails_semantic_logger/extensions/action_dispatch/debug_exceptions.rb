# Log actual exceptions, not a string representation
require "action_dispatch"

module ActionDispatch
  class DebugExceptions
    private

    undef_method :log_error
    def log_error(request, wrapper)
      Rails.application.deprecators.silence do
        return if !log_rescued_responses?(request) && wrapper.rescue_response?

        level     = request.get_header("action_dispatch.debug_exception_log_level")
        logger    = ActionController::Base.logger
        call_site = semantic_logger_call_site(wrapper, logger, level)
        logger.log(level, **semantic_logger_arguments(wrapper), call_site: call_site)
      end
    end

    # Returns the entry's call site, or nil when it records none: where the application raised the
    # exception, the first frame of its backtrace that the request's backtrace cleaner keeps before
    # Rails took over (see RailsSemanticLogger::ApplicationFrame.in_backtrace), or else false, as for a
    # routing error raised in middleware, rather than the frame that logs the entry.
    def semantic_logger_call_site(wrapper, logger, level)
      cleaner = wrapper.backtrace_cleaner || ::Rails.backtrace_cleaner
      RailsSemanticLogger.exception_call_site(wrapper.exception, cleaner, logger, level)
    end

    # Returns the arguments of the entry that logs the exception.
    #
    # When Rails' own log shows no backtrace for the exception, the entry has only its class and
    # message, and the exceptions that caused it, which Rails lists as "Caused by", with
    # Semantic Logger's `log_exception: :partial`, after the response's status, such as
    # "404 Not Found". The causes' backtraces, which Rails 8.0 and later also log, are left out too.
    # Otherwise a request for a missing route, such as /apple-touch-icon.png, would log dozens of
    # middleware frames that say nothing about the application.
    #
    # Rails decides that in ExceptionWrapper#exception_trace, which is empty only for the exceptions
    # in ExceptionWrapper.silent_exceptions (ActionController::RoutingError and
    # ActionDispatch::Http::MimeNegotiation::InvalidType, unless the application adds others), and
    # only when none of their frames is the application's once the request's backtrace cleaner has
    # cleaned them. Every other exception is logged with its backtrace, even with no application
    # frames, as in Rails' own log. The exception itself is left unchanged, since Rails renders it,
    # and error services hooked into Rails report it.
    #
    # ExceptionWrapper only reads backtrace_locations, so it finds no frames at all in a backtrace
    # set from Strings, such as with `raise error, message, backtrace`. That exception keeps its
    # backtrace.
    def semantic_logger_arguments(wrapper)
      exception = wrapper.exception
      # Rails wraps a SyntaxError in a proxy, which is not an Exception.
      exception = exception.__getobj__ if exception.is_a?(ActiveSupport::SyntaxErrorProxy)
      return {exception: exception} unless exception.backtrace_locations && wrapper.exception_trace.empty?

      status = wrapper.status_code
      {message: "#{status} #{::Rack::Utils::HTTP_STATUS_CODES[status]}", exception: exception, log_exception: :partial}
    end
  end
end
