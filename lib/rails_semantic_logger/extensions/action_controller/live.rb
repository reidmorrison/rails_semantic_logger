# Log actual exceptions, not a string representation
ActionController::Live
module ActionController::Live
  def log_error(exception)
    logger.fatal(exc)
  end
end
