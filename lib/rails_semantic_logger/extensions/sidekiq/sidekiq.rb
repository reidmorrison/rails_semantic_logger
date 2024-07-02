# Sidekiq patches
#
# To re-enable stdout logging for sidekiq server processes, add the following snippet to config/initializers/sidekiq.rb:
#   Sidekiq.configure_server do |config|
#     SemanticLogger.add_appender(io: $stdout, level: :debug, formatter: :color)
#   end
if Sidekiq::VERSION.to_i == 4
  require "sidekiq/exception_handler"
  require "sidekiq/logging"
  require "sidekiq/middleware/server/logging"
  require "sidekiq/processor"
  require "sidekiq/worker"
elsif Sidekiq::VERSION.to_i == 5
  require "sidekiq/exception_handler"
  require "sidekiq/job_logger"
  require "sidekiq/logging"
  require "sidekiq/worker"
elsif Sidekiq::VERSION.to_i == 6 && Sidekiq::VERSION.to_f < 6.5
  require "sidekiq/exception_handler"
  require "sidekiq/job_logger"
  require "sidekiq/worker"
elsif Sidekiq::VERSION.to_i == 6
  require "sidekiq/job_logger"
  require "sidekiq/worker"
else
  require "sidekiq/config"
  require "sidekiq/job_logger"
  require "sidekiq/job"
end

module Sidekiq
  # Sidekiq > v4
  if defined?(::Sidekiq::JobLogger)
    # Let Semantic Logger handle duration logging
    class JobLogger
      def call(item, queue, &block)
        klass  = item["wrapped"] || item["class"]
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger

        SemanticLogger.tagged(queue: queue) do
          # Latency is the time between when the job was enqueued and when it started executing.
          logger.info(
            "Start #perform",
            metric:        "sidekiq.queue.latency",
            metric_amount: job_latency_ms(item)
          )

          # Measure the duration of running the job
          logger.measure_info(
            "Completed #perform",
            on_exception_level: :error,
            log_exception:      :full,
            metric:             "sidekiq.job.perform",
            &block
          )
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

      def job_hash_context(job_hash)
        h         = {jid: job_hash["jid"]}
        h[:bid]   = job_hash["bid"] if job_hash["bid"]
        h[:tags]  = job_hash["tags"] if job_hash["tags"]
        h[:queue] = job_hash["queue"] if job_hash["queue"]
        h
      end

      def job_latency_ms(job)
        return unless job && job["enqueued_at"]

        (Time.now.to_f - job["enqueued_at"].to_f) * 1000
      end
    end
  end

  # Sidekiq <= v6
  if defined?(::Sidekiq::Logging)
    # Replace Sidekiq logging context
    module Logging
      def self.with_context(msg, &block)
        SemanticLogger.tagged(msg, &block)
      end

      def self.job_hash_context(job_hash)
        h         = {jid: job_hash["jid"]}
        h[:bid]   = job_hash["bid"] if job_hash["bid"]
        h[:queue] = job_hash["queue"] if job_hash["queue"]
        h
      end
    end
  end

  # Exception is already logged by Semantic Logger during the perform call
  if defined?(::Sidekiq::ExceptionHandler)
    # Sidekiq <= v6.5
    module ExceptionHandler
      class Logger
        def call(_exception, ctx)
          return if ctx.empty?

          job_hash = ctx[:job] || {}
          klass    = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
          logger   = klass ? SemanticLogger[klass] : Sidekiq.logger
          ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
        end
      end
    end
  elsif defined?(::Sidekiq::Config)
    # Sidekiq >= v7
    class Config
      remove_const :ERROR_HANDLER

      ERROR_HANDLER = ->(ex, ctx, cfg = Sidekiq.default_configuration) do
        unless ctx.empty?
          job_hash = ctx[:job] || {}
          klass    = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
          logger   = klass ? SemanticLogger[klass] : Sidekiq.logger
          ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
        end
      end
    end
  elsif Sidekiq.error_handlers.delete(Sidekiq::DEFAULT_ERROR_HANDLER)
    # Sidekiq >= 6.5
    # Replace default error handler if present
    Sidekiq.error_handlers << ->(ex, ctx) do
      unless ctx.empty?
        job_hash = ctx[:job] || {}
        klass = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger
        ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
      end
    end
  end

  # Logging within each worker should use its own logger
  case Sidekiq::VERSION.to_i
  when 4
    module Worker
      def self.included(base)
        if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }
          raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}"
        end

        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
        base.class_attribute :sidekiq_options_hash
        base.class_attribute :sidekiq_retry_in_block
        base.class_attribute :sidekiq_retries_exhausted_block
      end
    end
  when 5
    module Worker
      def self.included(base)
        if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }
          raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}"
        end

        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
        base.sidekiq_class_attribute :sidekiq_options_hash
        base.sidekiq_class_attribute :sidekiq_retry_in_block
        base.sidekiq_class_attribute :sidekiq_retries_exhausted_block
      end
    end
  when 6
    module Worker
      def self.included(base)
        if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }
          raise ArgumentError, "Sidekiq::Worker cannot be included in an ActiveJob: #{base.name}"
        end

        base.include(Options)
        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
      end
    end
  else
    module Job
      def self.included(base)
        if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }
          raise ArgumentError, "Sidekiq::Job cannot be included in an ActiveJob: #{base.name}"
        end

        base.include(Options)
        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
      end
    end
  end

  if defined?(::Sidekiq::Middleware::Server::Logging)
    # Sidekiq v4
    # Convert string to machine readable format
    class Processor
      def log_context(job_hash)
        h         = {jid: job_hash["jid"]}
        h[:bid]   = job_hash["bid"] if job_hash["bid"]
        h[:queue] = job_hash["queue"] if job_hash["queue"]
        h
      end
    end

    # Let Semantic Logger handle duration logging
    module Middleware
      module Server
        class Logging
          def call(worker, item, queue)
            SemanticLogger.tagged(queue: queue) do
              worker.logger.info(
                "Start #perform",
                metric:        "sidekiq.queue.latency",
                metric_amount: job_latency_ms(item)
              )
              worker.logger.measure_info(
                "Completed #perform",
                on_exception_level: :error,
                log_exception:      :full,
                metric:             "sidekiq.job.perform"
              ) { yield }
            end
          end

          def job_latency_ms(job)
            return unless job && job["enqueued_at"]

            (Time.now.to_f - job["enqueued_at"].to_f) * 1000
          end
        end
      end
    end
  end
end
