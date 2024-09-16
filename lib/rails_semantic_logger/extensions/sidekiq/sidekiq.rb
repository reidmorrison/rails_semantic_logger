# Sidekiq patches
if Sidekiq::VERSION.to_i == 4
  require "sidekiq/logging"
  require "sidekiq/middleware/server/logging"
  require "sidekiq/processor"
elsif Sidekiq::VERSION.to_i == 5
  require "sidekiq/logging"
end

module Sidekiq
  # Sidekiq v4 & v5
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

  # Sidekiq v4
  if defined?(::Sidekiq::Middleware::Server::Logging)
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
          # rubocop:disable Style/ExplicitBlockArgument
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
