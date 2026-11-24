module RailsSemanticLogger
  module Metrics
    # Records the metrics of Active Job. Enqueuing and performing a job follow OpenTelemetry's
    # messaging conventions, with `active_job` as the messaging system, as OpenTelemetry's
    # active_job instrumentation names it. The rest has no convention, so it is named under
    # `active_job`, the system's name.
    #
    # A job that Active Job runs on Sidekiq is also recorded by Sidekiq's job logger, under the
    # messaging system `sidekiq`: sum one system or the other, never both.
    class ActiveJob < Subscriber
      SYSTEM = "active_job".freeze

      def enqueue(event)
        enqueued("enqueue", event)
      end

      def enqueue_at(event)
        enqueued("enqueue_at", event)
      end

      # Several jobs enqueued at once, with perform_all_later.
      def enqueue_all(event)
        payload = event.payload
        jobs    = payload[:jobs] || []
        jobs.select(&:successfully_enqueued?).group_by { |job| job_dimensions(job) }.each do |dimensions, sent|
          increment("messaging.client.sent.messages", dimensions, sent.size)
        end

        dimensions = operation_dimensions("enqueue_all", "send")
        dimensions["messaging.active_job.adapter.name"] = adapter_name(payload[:adapter]) if payload[:adapter]
        dimensions["error.type"]                        = "partial" if jobs.any? { |job| !job.successfully_enqueued? }
        time("messaging.client.operation.duration", event, dimensions)
      end

      # How long the job waited in its queue: from when it was due, the time it was scheduled for or
      # else when it was enqueued, until it started. No convention covers it.
      def perform_start(event)
        job = event.payload[:job]
        due = job.scheduled_at || job.enqueued_at
        return unless due

        record_duration("active_job.queue.duration", [(Time.now - due) * 1000, 0].max, job_dimensions(job))
      end

      def perform(event)
        payload    = event.payload
        dimensions = job_dimensions(payload[:job]).merge("messaging.operation.name" => "process")
        error_type = error_type(payload[:exception_object], payload[:aborted])
        dimensions["error.type"] = error_type if error_type
        time("messaging.process.duration", event, dimensions)
      end

      def enqueue_retry(event)
        increment("active_job.retries", failure_dimensions(event.payload))
      end

      def retry_stopped(event)
        increment("active_job.exhausted_retries", failure_dimensions(event.payload))
      end

      def discard(event)
        increment("active_job.discards", failure_dimensions(event.payload))
      end

      # Continuations (Rails 8.1+).
      def interrupt(event)
        increment("active_job.interrupts", job_dimensions(event.payload[:job]))
      end

      def resume(event)
        increment("active_job.resumes", job_dimensions(event.payload[:job]))
      end

      def step(event)
        payload    = event.payload
        dimensions = job_dimensions(payload[:job])
        dimensions["active_job.step.name"] = payload[:step].name.to_s if payload[:step]
        time("active_job.step.duration", event, dimensions)
      end

      private

      # Counts a job as sent only once it was enqueued, as the convention asks, and times the attempt
      # either way.
      def enqueued(operation, event)
        payload = event.payload
        job     = payload[:job]
        error   = enqueue_error(payload)
        increment("messaging.client.sent.messages", job_dimensions(job)) unless error || payload[:aborted]

        dimensions = job_dimensions(job).merge(operation_dimensions(operation, "send"))
        dimensions["messaging.active_job.adapter.name"] = adapter_name(payload[:adapter]) if payload[:adapter]
        error_type = error_type(error, payload[:aborted])
        dimensions["error.type"] = error_type if error_type
        time("messaging.client.operation.duration", event, dimensions)
      end

      def job_dimensions(job)
        {
          "messaging.system.name"          => SYSTEM,
          "messaging.destination.name"     => job.queue_name.to_s,
          "messaging.active_job.job.class" => job.class.name
        }
      end

      def operation_dimensions(operation, type)
        {
          "messaging.system.name"    => SYSTEM,
          "messaging.operation.name" => operation,
          "messaging.operation.type" => type
        }
      end

      def failure_dimensions(payload)
        dimensions = job_dimensions(payload[:job])
        dimensions["error.type"] = payload[:error].class.name if payload[:error]
        dimensions
      end

      # The exception class, or "aborted" when a callback halted the job.
      def error_type(exception, aborted)
        return exception.class.name if exception

        "aborted" if aborted
      end

      # Rails reports an enqueue failure either as the event's exception or as the job's enqueue_error.
      def enqueue_error(payload)
        payload[:exception_object] || (payload[:job].enqueue_error if payload[:job].respond_to?(:enqueue_error))
      end

      def adapter_name(adapter)
        ::ActiveJob.adapter_name(adapter)
      end
    end
  end
end
