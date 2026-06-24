module RailsSemanticLogger
  module Sidekiq
    class JobLogger
      class << self
        attr_writer :perform_messages

        def perform_messages
          instance_variable_defined?(:@perform_messages) ? @perform_messages : true
        end
      end

      # Sidekiq 6.5 does not take any arguments, whereas v7 is given a logger
      def initialize(*_args)
      end

      def call(item, queue, &block)
        klass  = item["wrapped"] || item["class"]
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger

        SemanticLogger.tagged(queue: queue) do
          if perform_messages_enabled?
          # Latency is the time between when the job was enqueued and when it started executing.
            logger.info(
              "Start #perform",
              metric:        "sidekiq.queue.latency",
              metric_amount: job_latency_ms(item)
            )
          end

          # Measure the duration of running the job
          if perform_messages_enabled?
            logger.measure_info(
              "Completed #perform",
              on_exception_level: :error,
              log_exception:      :full,
              metric:             "sidekiq.job.perform",
              &block
            )
          else
            yield if block_given?
          end
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

      private

      def perform_messages_enabled?
        self.class.perform_messages != false
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

        enqueued_at = job["enqueued_at"]
        if enqueued_at.is_a?(Float)
          # Sidekiq <= 7: seconds since epoch
          (Time.now.to_f - enqueued_at) * 1000
        else
          # Sidekiq 8+: milliseconds since epoch
          now = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
          now - enqueued_at
        end
      end
    end
  end
end
