module RailsSemanticLogger
  module Sidekiq
    class JobLogger
      # Job attributes copied into the logging context, matching Sidekiq's own defaults.
      # Sidekiq 8 makes this configurable via `config[:logged_job_attributes]`.
      DEFAULT_LOGGED_JOB_ATTRIBUTES = %w[bid tags].freeze

      class << self
        attr_writer :perform_messages, :metrics

        # Whether to record the job metrics. The engine sets it from config.rails_semantic_logger.metrics.
        def metrics
          instance_variable_defined?(:@metrics) ? @metrics : true
        end

        def perform_messages
          instance_variable_defined?(:@perform_messages) ? @perform_messages : true
        end
      end

      # Sidekiq 7 passes its logger, whereas Sidekiq 8 passes its config.
      def initialize(arg = nil)
        @config = arg if arg.respond_to?(:[])
      end

      # How long a job waited in its queue, from when it was enqueued until it started: no OpenTelemetry
      # semantic convention covers it, so it is named after the system, Sidekiq.
      QUEUE_DURATION = "sidekiq.queue.duration".freeze

      # How long a job ran: OpenTelemetry's messaging convention for processing a message.
      PROCESS_DURATION = "messaging.process.duration".freeze

      def call(item, queue, &block)
        klass  = item["wrapped"] || item["class"]
        logger = klass ? SemanticLogger[klass] : Sidekiq.logger

        SemanticLogger.tagged(queue: queue) do
          dimensions = {"messaging.system.name" => "sidekiq", "messaging.destination.name" => queue}

          latency = job_latency_ms(item)
          metrics.time(QUEUE_DURATION, duration: latency, dimensions: dimensions) if latency && self.class.metrics
          logger.info("Start #perform", call_site: false) if perform_messages_enabled?

          process(logger, klass, dimensions, &block)
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

      # Runs the job, logging it unless perform messages are turned off, and records how long it ran
      # whether or not it is logged: the settings that turn off the perform messages are about logging.
      def process(logger, klass, dimensions, &block)
        start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        error = nil
        if perform_messages_enabled?
          logger.measure_info(
            "Completed #perform",
            on_exception_level: :error,
            log_exception:      :full,
            call_site:          false,
            &block
          )
        elsif block
          yield
        end
      rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then raised again
        error = e
        raise
      ensure
        if self.class.metrics
          duration_ms = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000
          metrics.time(PROCESS_DURATION, duration:   duration_ms,
                                         dimensions: process_dimensions(dimensions, klass, error))
        end
      end

      # OpenTelemetry names a system-specific attribute after its system, as `messaging.sidekiq.*`.
      def process_dimensions(dimensions, klass, error)
        process = dimensions.merge("messaging.operation.name" => "process")
        process["messaging.sidekiq.job.class"] = klass if klass
        # An anonymous exception class has no name: OpenTelemetry's fallback for an unknown error.
        process["error.type"]                  = job_error(error).class.name || "_OTHER" if error
        process
      end

      # The exception the job raised. When Sidekiq will retry the job, its retrier catches that exception
      # and raises Sidekiq::JobRetry::Handled in its place, from the rescue, so it is the cause.
      def job_error(error)
        handled = defined?(::Sidekiq::JobRetry::Handled) && error.is_a?(::Sidekiq::JobRetry::Handled)
        handled && error.cause ? error.cause : error
      end

      # Records the job metrics. Not the job's logger, which can be Sidekiq's, and the application can
      # make that a plain Ruby Logger, which records no metrics.
      def metrics
        RailsSemanticLogger::Metrics.logger
      end

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
