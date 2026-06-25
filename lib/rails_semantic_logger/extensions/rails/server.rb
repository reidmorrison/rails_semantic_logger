# Patch the Rails::Server log_to_stdout so that it logs via SemanticLogger
require "rails"

module Rails
  class Server
    private

    undef_method :log_to_stdout if method_defined?(:log_to_stdout)
    def log_to_stdout
      wrapped_app # touch the app so the logger is set up

      RailsSemanticLogger.add_server_appenders
    end
  end
end
