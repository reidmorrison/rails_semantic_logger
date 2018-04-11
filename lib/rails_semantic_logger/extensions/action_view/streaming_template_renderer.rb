# Log actual exceptions, not a string representation
ActionView::StreamingTemplateRenderer

module ActionView
  class StreamingTemplateRenderer
    class Body
      private

      def log_error(exception)
        ActionView::Base.logger.fatal(exception)
      end
    end
  end
end
