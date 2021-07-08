# Log actual exceptions, not a string representation
ActionView::StreamingTemplateRenderer

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
