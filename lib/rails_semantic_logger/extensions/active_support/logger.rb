require "active_support/logger"

module ActiveSupport
  # More hacks to try and stop Rails from being it's own worst enemy.
  class Logger
    class << self
      undef :logger_outputs_to?

      # Prevent broadcasting since SemanticLogger already supports multiple loggers
      if method_defined?(:broadcast)
        undef :broadcast
        def broadcast(_logger)
          Module.new
        end
      end
    end

    # Prevent Console from trying to merge loggers
    def self.logger_outputs_to?(*_args)
      true
    end

    def self.new(*_args, **_kwargs)
      SemanticLogger[self]
    end
  end
end
