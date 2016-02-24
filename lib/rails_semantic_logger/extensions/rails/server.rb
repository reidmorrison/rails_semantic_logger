# Patch the Rails::Server log_to_stdout so that it logs via SemanticLogger
Rails::Server
module Rails #:nodoc:
  class Server #:nodoc:
    private

    def log_to_stdout
      SemanticLogger.add_appender(io: $stdout, formatter: :color)
    end
  end
end
