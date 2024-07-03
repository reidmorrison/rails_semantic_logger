module RailsSemanticLogger
  module Sidekiq
    module Defaults
      # Prevent exception logging during standard error handling since the Job Logger below already logs the exception.
      if ::Sidekiq::VERSION.to_f < 7.2
        ERROR_HANDLER = ->(ex, ctx) do
          unless ctx.empty?
            job_hash = ctx[:job] || {}
            klass    = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
            logger   = klass ? SemanticLogger[klass] : Sidekiq.logger
            ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
          end
        end
      else
        ERROR_HANDLER = ->(ex, ctx, _default_configuration) do
          unless ctx.empty?
            job_hash = ctx[:job] || {}
            klass    = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
            logger   = klass ? SemanticLogger[klass] : Sidekiq.logger
            ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
          end
        end
      end

      # Returns the default logger after removing from the supplied list.
      # Returns [nil] when the default logger was not present.
      def self.delete_default_error_handler(error_handlers)
        return error_handlers.delete(::Sidekiq::Config::ERROR_HANDLER) if defined?(::Sidekiq::Config::ERROR_HANDLER)
        return error_handlers.delete(::Sidekiq::DEFAULT_ERROR_HANDLER) if defined?(::Sidekiq::DEFAULT_ERROR_HANDLER)

        return unless defined?(::Sidekiq::ExceptionHandler)
        existing = error_handlers.find { |handler| handler.is_a?(::Sidekiq::ExceptionHandler::Logger) }
        return config.error_handlers.delete(existing) if existing
      end
    end
  end
end
