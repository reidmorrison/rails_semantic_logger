module RailsSemanticLogger
  module Sidekiq
    module Defaults
      # Prevent exception logging during standard error handling since the Job Logger below already logs the exception.
      # Logs the remaining Sidekiq context at :info (matching upstream Sidekiq's default handler) rather than :warn,
      # since the exception itself is already logged at :error by the Job Logger.
      # Sidekiq 7.1.6+ calls error handlers with a third config argument; earlier 7.x versions pass only two.
      ERROR_HANDLER =
        lambda do |_ex, ctx, _config = nil|
          unless ctx.empty?
            job_hash = ctx[:job] || {}
            klass    = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
            logger   = klass ? SemanticLogger[klass] : ::Sidekiq.logger
            ctx[:context] ? logger.info(ctx[:context], ctx) : logger.info(ctx)
          end
        end

      # Returns the default error handler after removing it from the supplied list.
      # Returns [nil] when the default handler was not present.
      def self.delete_default_error_handler(error_handlers)
        error_handlers.delete(::Sidekiq::Config::ERROR_HANDLER)
      end
    end
  end
end
