require "active_support/logger"

module ActiveSupport
  # More hacks to try and stop Rails from being its own worst enemy.
  class Logger
    class << self
      # Keep a handle on the genuine constructor so that callers which supply a
      # real log destination still get a real logger (see #new below).
      alias _semantic_logger_original_new new

      undef :logger_outputs_to?

      # Prevent Rails from trying to merge/broadcast loggers (e.g. ActiveRecord's
      # `console` hook and `rails server`'s log_to_stdout). SemanticLogger already
      # multiplexes through its own appenders, and SemanticLogger::Logger does not
      # implement #broadcast_to, so the merge path would otherwise raise.
      def logger_outputs_to?(*_args)
        true
      end

      # Historically every `ActiveSupport::Logger.new(...)` call was redirected to
      # SemanticLogger, silently discarding the requested destination. That broke
      # third-party callers such as Webpacker's `ActiveSupport::Logger.new(STDOUT)`,
      # whose output never reached STDOUT (issue #141). Only redirect to
      # SemanticLogger when no destination is supplied; otherwise honor the caller
      # and build a genuine logger pointed at the requested destination.
      def new(*args, **kwargs)
        if args.empty? && kwargs.empty?
          SemanticLogger[self]
        else
          _semantic_logger_original_new(*args, **kwargs)
        end
      end
    end
  end
end
