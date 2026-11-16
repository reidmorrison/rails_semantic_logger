# Log actual exceptions, not a string representation
require "action_view/renderer/streaming_template_renderer"

module ActionView
  class StreamingTemplateRenderer
    class Body
      private

      undef_method :log_error
      def log_error(exception)
        logger = ActionView::Base.logger
        logger.fatal(
          exception: exception,
          call_site: RailsSemanticLogger.exception_call_site(exception, ::Rails.backtrace_cleaner, logger, :fatal)
        )
      end
    end
  end
end
