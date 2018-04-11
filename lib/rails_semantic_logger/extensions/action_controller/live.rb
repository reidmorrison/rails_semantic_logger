# Log actual exceptions, not a string representation
ActionController::Live
module ActionController
  module Live
    def log_error(exception)
      logger.fatal(exception)
    end
  end
end
