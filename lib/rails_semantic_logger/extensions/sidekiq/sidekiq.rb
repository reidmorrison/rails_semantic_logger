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
      def call(item, queue)
        klass  = item["wrapped"] || item["class"]
        metric = "Sidekiq/#{klass}/perform" if klass
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger
        logger.info("Start #perform")
        logger.measure_info(
          "Completed #perform",
          on_exception_level: :error,
          log_exception:      :full,
          metric:             metric
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

      def job_hash_context(job_hash)
        h        = {
          class: job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"],
          jid:   job_hash["jid"]
        }
        h[:bid]  = job_hash["bid"] if job_hash["bid"]
        h[:tags] = job_hash["tags"] if job_hash["tags"]
        h
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
        klass       = job_hash["wrapped"] || job_hash["class"]
        event       = { class: klass, jid: job_hash["jid"] }
        event[:bid] = job_hash["bid"] if job_hash["bid"]
        event
      end
    end
  end

  # Exception is already logged by Semantic Logger during the perform call
  # Sidekiq <= v6.5
  if defined?(::Sidekiq::ExceptionHandler)
    module ExceptionHandler
      class Logger
        def call(ex, ctx)
          unless ctx.empty?
            job_hash = ctx[:job] || {}
            klass = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
            logger = klass ? SemanticLogger[klass] : Sidekiq.logger
            ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
          end
        end
      end
    end
  # Sidekiq >= v7
  elsif defined?(::Sidekiq::Config)
    class Config
      remove_const :ERROR_HANDLER

      ERROR_HANDLER = ->(ex, ctx, cfg = Sidekiq.default_configuration) do
        unless ctx.empty?
          job_hash = ctx[:job] || {}
          klass = job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"]
          logger = klass ? SemanticLogger[klass] : Sidekiq.logger
          ctx[:context] ? logger.warn(ctx[:context], ctx) : logger.warn(ctx)
        end
      end
    end
  else
    # Sidekiq >= 6.5
    Sidekiq.error_handlers.delete(Sidekiq::DEFAULT_ERROR_HANDLER)
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
  if Sidekiq::VERSION.to_i == 4
    module Worker
      def self.included(base)
        raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
        base.class_attribute :sidekiq_options_hash
        base.class_attribute :sidekiq_retry_in_block
        base.class_attribute :sidekiq_retries_exhausted_block
      end
    end
  elsif Sidekiq::VERSION.to_i == 5
    module Worker
      def self.included(base)
        raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
        base.sidekiq_class_attribute :sidekiq_options_hash
        base.sidekiq_class_attribute :sidekiq_retry_in_block
        base.sidekiq_class_attribute :sidekiq_retries_exhausted_block
      end
    end
  elsif Sidekiq::VERSION.to_i == 6
    module Worker
      def self.included(base)
        raise ArgumentError, "Sidekiq::Worker cannot be included in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

        base.include(Options)
        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
      end
    end
  else
    module Job
      def self.included(base)
        raise ArgumentError, "Sidekiq::Job cannot be included in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

        base.include(Options)
        base.extend(ClassMethods)
        base.include(SemanticLogger::Loggable)
      end
    end
  end

  if Sidekiq::VERSION.to_i == 4
    # Convert string to machine readable format
    class Processor
      def log_context(job_hash)
        klass       = job_hash["wrapped"] || job_hash["class"]
        event       = { class: klass, jid: job_hash["jid"] }
        event[:bid] = job_hash["bid"] if job_hash["bid"]
        event
      end
    end

    # Let Semantic Logger handle duration logging
    module Middleware
      module Server
        class Logging
          def call(worker, item, queue)
            worker.logger.info("Start #perform")
            worker.logger.measure_info(
              "Completed #perform",
              on_exception_level: :error,
              log_exception:      :full,
              metric:             "Sidekiq/#{worker.class.name}/perform"
            ) do
              yield
            end
          end
        end
      end
    end
  end
end
