# Log actual exceptions, not a string representation
ActionDispatch::DebugExceptions
class ActionDispatch::DebugExceptions
  private
  def log_error(request, wrapper)
    ActiveSupport::Deprecation.silence do
      ActionController::Base.logger.fatal(wrapper.exception)
    end
  end
end

