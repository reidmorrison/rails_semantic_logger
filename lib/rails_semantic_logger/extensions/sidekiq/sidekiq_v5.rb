# Sidekiq v5 patches
#
# To re-enable stdout logging for sidekiq server processes, add the following snippet to config/initializers/sidekiq.rb:
#   Sidekiq.configure_server do |config|
#     SemanticLogger.add_appender(io: $stdout, level: :debug, formatter: :color)
#   end
require "sidekiq/exception_handler"
require "sidekiq/job_logger"
require "sidekiq/logging"
require "sidekiq/worker"
# Replace Sidekiq context with Semantic Logger
module Sidekiq
  module Logging
    def self.with_context(msg, &block)
      SemanticLogger.tagged(msg, &block)
    end

    def self.job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      klass       = job_hash["wrapped"] || job_hash["class"]
      event       = { class: klass, jid: job_hash["jid"] }
      event[:bid] = job_hash["bid"] if job_hash["bid"]
      event
    end
  end

  # Let Semantic Logger handle duration logging
  class JobLogger
    def call(item, queue)
      logger.info("Start #perform")
      klass = item["wrapped"] || item["class"]
      metric = "Sidekiq/#{klass}/perform" if klass
      logger.measure_info(
        "Completed #perform",
        on_exception_level: :error,
        log_exception: :full,
        metric: metric
      ) do
        yield
      end
    end
  end

  # Logging within each worker should use its own logger
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

  # Exception is already logged by Semantic Logger during the perform call
  module ExceptionHandler
    class Logger
      def call(ex, ctxHash)
        Sidekiq.logger.warn(ctxHash) if !ctxHash.empty?
      end
    end
  end
end
