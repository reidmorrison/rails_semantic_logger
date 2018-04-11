# Log actual exceptions, not a string representation
ActionView::StreamingTemplateRenderer

class ActionView::StreamingTemplateRenderer
  class Body
    private
    def log_error(exception)
      ActionView::Base.logger.fatal(exception)
    end
  end
end
