# Log actual exceptions, not a string representation.
#
# Patched once Action Controller has loaded, because loading ActionController::Live also loads
# ActionDispatch::Response, and Rails 8.2+ reports that when it happens before the application
# has initialized.
ActiveSupport.on_load(:action_controller, run_once: true) do
  ActionController::Live.module_eval do
    undef_method :log_error
    def log_error(exception)
      logger.fatal(
        exception: exception,
        call_site: RailsSemanticLogger.exception_call_site(exception, Rails.backtrace_cleaner, logger, :fatal)
      )
    end
  end
end
