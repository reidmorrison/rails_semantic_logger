module RailsSemanticLogger
  module Sidekiq
    class JobLogger
      # Job attributes copied into the logging context, matching Sidekiq's own defaults.
      # Sidekiq 8 makes this configurable via `config[:logged_job_attributes]`.
      DEFAULT_LOGGED_JOB_ATTRIBUTES = %w[bid tags].freeze

      class << self
        attr_writer :perform_messages

        def perform_messages
          instance_variable_defined?(:@perform_messages) ? @perform_messages : true
        end
      end

      # Sidekiq 7 passes its logger, whereas Sidekiq 8 passes its config.
      def initialize(arg = nil)
        @config = arg if arg.respond_to?(:[])
      end

      def call(item, queue, &block)
        klass  = item["wrapped"] || item["class"]
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger

        SemanticLogger.tagged(queue: queue) do
          if perform_messages_enabled?
            # Latency is the time between when the job was enqueued and when it started executing.
            latency = job_latency_ms(item)
            logger.time("sidekiq.queue.latency", duration: latency) if latency
            logger.info("Start #perform", call_site: false)
          end

          # Measure the duration of running the job
          if perform_messages_enabled?
            logger.measure_info(
              "Completed #perform",
              on_exception_level: :error,
              log_exception:      :full,
              metric:             "sidekiq.job.perform",
              call_site:          false,
              &block
            )
          elsif block_given?
            yield
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
        return false if @config && @config[:skip_default_job_logging]

        self.class.perform_messages != false
      end

      def job_hash_context(job_hash)
        h = {jid: job_hash["jid"], class: job_hash["wrapped"] || job_hash["class"]}
        logged_job_attributes.each do |attr|
          h[attr.to_sym] = job_hash[attr] if job_hash.key?(attr)
        end
        h[:queue] = job_hash["queue"] if job_hash["queue"]
        h
      end

      def logged_job_attributes
        (@config && @config[:logged_job_attributes]) || DEFAULT_LOGGED_JOB_ATTRIBUTES
      end

      # Never negative: the clock of the host that enqueued the job can be ahead of this one's, and a
      # negative duration is not a latency.
      def job_latency_ms(job)
        return unless job && job["enqueued_at"]

        enqueued_at = job["enqueued_at"]
        if enqueued_at.is_a?(Float)
          # Sidekiq <= 7: seconds since epoch
          [(Time.now.to_f - enqueued_at) * 1000, 0.0].max
        else
          # Sidekiq 8+: milliseconds since epoch
          now = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
          [now - enqueued_at, 0].max
        end
      end
    end
  end
end
