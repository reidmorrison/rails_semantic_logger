# Log actual exceptions, not a string representation
require "action_controller"

module ActionController
  module Live
    undef_method :log_error
    def log_error(exception)
      logger.fatal(exception)
    end
  end
end
