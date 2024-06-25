# Sidekiq v4 patches
#
# To re-enable stdout logging for sidekiq server processes, add the following snippet to config/initializers/sidekiq.rb:
#   Sidekiq.configure_server do |config|
#     SemanticLogger.add_appender(io: $stdout, level: :debug, formatter: :color)
#   end
require "sidekiq/logging"
# Replace Sidekiq context with Semantic Logger
module Sidekiq
  module Logging
    def self.with_context(msg, &block)
      SemanticLogger.tagged(msg, &block)
    end
  end
end

require "sidekiq/processor"
# Convert string to machine readable format
module Sidekiq
  class Processor
    def log_context(item)
      event       = { jid: item["jid".freeze] }
      event[:bid] = item["bid".freeze] if item["bid".freeze]
      event
    end
  end
end

require "sidekiq/middleware/server/logging"
# Let Semantic Logger handle duration logging
module Sidekiq
  module Middleware
    module Server
      class Logging
        def call(worker, item, queue)
          worker.logger.info("Start #perform")
          worker.logger.measure_info(
            "Completed #perform",
            on_exception_level: :error,
            log_exception: :full,
            metric: "Sidekiq/#{worker.class.name}/perform"
          ) do
            yield
          end
        end
      end
    end
  end
end

require "sidekiq/worker"
# Logging within each worker should use its own logger
module Sidekiq
  module Worker
    attr_accessor :jid

    def self.included(base)
      raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

      base.extend(ClassMethods)
      base.include(SemanticLogger::Loggable)
      base.class_attribute :sidekiq_options_hash
      base.class_attribute :sidekiq_retry_in_block
      base.class_attribute :sidekiq_retries_exhausted_block
    end
  end
end

require "sidekiq/exception_handler"
# Exception is already logged by Semantic Logger during the perform call
module Sidekiq
  module ExceptionHandler
    class Logger
      def call(ex, ctxHash)
        Sidekiq.logger.warn(ctxHash) if !ctxHash.empty?
      end
    end
  end
end

