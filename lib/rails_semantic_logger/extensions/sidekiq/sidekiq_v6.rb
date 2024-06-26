# Sidekiq v6.2 patches
#
# To re-enable stdout logging for sidekiq server processes, add the following snippet to config/initializers/sidekiq.rb:
#   Sidekiq.configure_server do |config|
#     SemanticLogger.add_appender(io: $stdout, level: :debug, formatter: :color)
#   end
require "sidekiq/exception_handler"
require "sidekiq/job_logger"
require "sidekiq/worker"
module Sidekiq
  # Let Semantic Logger handle duration logging
  class JobLogger
    def call(item, queue)
      klass = item["wrapped"] || item["class"]
      metric = "Sidekiq/#{klass}/perform" if klass
      logger = klass ? SemanticLogger[klass] : Sidekiq.logger
      logger.info("Start #perform")
      logger.measure_info(
        "Completed #perform",
        on_exception_level: :error,
        log_exception: :full,
        metric: metric
      ) do
        yield
      end
    end

    def prepare(job_hash, &block)
      level = job_hash["log_level"]
      if level
        SemanticLogger.silence(level) do
          SemanticLogger.tagged(job_hash_context(job_hash), &block)
        end
      else
        SemanticLogger.tagged(job_hash_context(job_hash), &block)
      end
    end
  end

  # Logging within each worker should use its own logger
  module Worker
    def self.included(base)
      raise ArgumentError, "Sidekiq::Worker cannot be included in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

      base.include(Options)
      base.extend(ClassMethods)
      base.include(SemanticLogger::Loggable)
    end
  end

  # Exception is already logged by Semantic Logger during the perform call
  module ExceptionHandler
    class Logger
      def call(ex, ctx)
        Sidekiq.logger.warn(ctx) if !ctx.empty?
      end
    end
  end
end
