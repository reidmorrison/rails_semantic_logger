require "active_support/logger"

module ActiveSupport
  # More hacks to try and stop Rails from being it's own worst enemy.
  class Logger
    class << self
      undef :logger_outputs_to?

      # Prevent broadcasting since SemanticLogger already supports multiple loggers
      if method_defined?(:broadcast)
        undef :broadcast
        def broadcast(logger)
          Module.new
        end
      end
    end

    # Prevent Console from trying to merge loggers
    def self.logger_outputs_to?(*args)
      true
    end

    def self.broadcast(logger)
      Module.new
    end

    def self.new(*args, **kwargs)
      SemanticLogger[self]
    end
  end
end
