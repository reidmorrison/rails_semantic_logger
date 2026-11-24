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
        error   = payload[:exception_object]
        count   = payload[:enqueued_count].to_i
        sent    = sent_jobs(jobs, count, error)
        if sent
          sent.group_by { |job| job_dimensions(job) }.each do |dimensions, group|
            increment("messaging.client.sent.messages", dimensions, group.size)
          end
        else
          count_unmarked(jobs, count)
        end

        dimensions = operation_dimensions("enqueue_all", "send")
        dimensions["messaging.active_job.adapter.name"] = adapter_name(payload[:adapter]) if payload[:adapter]
        failure = enqueue_all_failure(jobs, sent ? sent.size : count, error)
        dimensions["error.type"] = failure if failure
        time("messaging.client.operation.duration", event, dimensions)
      end

      # How long the job waited in its queue: from when it was due, the later of the time it was
      # scheduled for and when it was last enqueued, until it started. No convention covers it.
      #
      # Only a job taken from a queue has enqueued_at: one performed at once, even with a wait, never
      # waited in a queue.
      def perform_start(event)
        job = event.payload[:job]
        return unless job.enqueued_at

        due = [to_time(job.scheduled_at), to_time(job.enqueued_at)].compact.max
        return unless due

        record_duration("active_job.queue.duration", [(Time.now - due) * 1000, 0].max, job_dimensions(job))
      end

      def perform(event)
        payload    = event.payload
        dimensions = job_dimensions(payload[:job]).merge("messaging.operation.name" => "process")
        failure = failure_type(payload[:exception_object], payload[:aborted])
        dimensions["error.type"] = failure if failure
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
        dimensions["active_job.step.name"]        = payload[:step].name.to_s if payload[:step]
        dimensions["active_job.step.interrupted"] = payload[:interrupted] == true
        # An interrupted step raises Interrupt through the instrumentation, which is not a failure.
        error = payload[:exception_object] unless payload[:interrupted]
        dimensions["error.type"] = error_type(error) if error
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
        failure = failure_type(error, payload[:aborted])
        dimensions["error.type"] = failure if failure
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
        dimensions["error.type"] = error_type(payload[:error]) if payload[:error]
        dimensions
      end

      # The exception's error.type, or "aborted" when a callback halted the job.
      def failure_type(exception, aborted)
        return error_type(exception) if exception

        "aborted" if aborted
      end

      # The error.type of enqueue_all: the exception it raised, "failed" when no job was enqueued, and
      # "partial" when only some were.
      def enqueue_all_failure(jobs, enqueued, error)
        return error_type(error) if error
        return if enqueued >= jobs.size

        enqueued.zero? ? "failed" : "partial"
      end

      # An adapter that enqueues jobs all at once, as Sidekiq's does, returns how many it enqueued and
      # marks none, so when it enqueued only some, which ones is not known: they are counted by the
      # jobs' queue and class when all share them, else by the system alone.
      def count_unmarked(jobs, count)
        return unless count.positive?

        groups     = jobs.map { |job| job_dimensions(job) }.uniq
        dimensions = groups.size == 1 ? groups.first : {"messaging.system.name" => SYSTEM}
        increment("messaging.client.sent.messages", dimensions, count)
      end

      # Rails reports an enqueue failure either as the event's exception or as the job's enqueue_error.
      # The job's is read only when it was not enqueued: Rails 7.2 keeps the enqueue_error of an earlier
      # attempt when the same job is enqueued again.
      def enqueue_error(payload)
        return payload[:exception_object] if payload[:exception_object]

        job = payload[:job]
        return if job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?

        job.enqueue_error if job.respond_to?(:enqueue_error)
      end

      # The jobs that enqueue_all sent, when it is known which: all of them when the adapter enqueued as
      # many as it was given, otherwise those marked as enqueued.
      #
      # Nil when the marks do not agree with the adapter's count: an adapter that enqueues them all at
      # once, as Sidekiq's does, marks none, and a job enqueued before keeps its mark.
      def sent_jobs(jobs, enqueued_count, error)
        return jobs if error.nil? && enqueued_count == jobs.size

        marked = jobs.select(&:successfully_enqueued?)
        marked if error || marked.size == enqueued_count
      end

      # A time Active Job holds as a Time, a Date (wait_until: Date.tomorrow), or seconds since the epoch.
      def to_time(value)
        case value
        when Numeric then Time.at(value)
        when nil then nil
        else value.to_time
        end
      end

      def adapter_name(adapter)
        ::ActiveJob.adapter_name(adapter)
      end
    end
  end
end
