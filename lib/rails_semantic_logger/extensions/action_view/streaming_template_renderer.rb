# Log actual exceptions, not a string representation
require "action_view/renderer/streaming_template_renderer"

module ActionView
  class StreamingTemplateRenderer
    class Body
      private

      undef_method :log_error
      def log_error(exception)
        ActionView::Base.logger.fatal(exception)
      end
    end
  end
end
