require "active_job"

# This subscriber is a reimplementation of Rails' own ActiveJob::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/activejob/lib/active_job/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/activejob/lib/active_job/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/activejob/lib/active_job/log_subscriber.rb
#
# Event coverage by Rails version:
#   7.2 / 8.0: enqueue, enqueue_at, enqueue_all, perform_start, perform,
#              enqueue_retry, retry_stopped, discard
#   8.1 adds (ActiveJob Continuations): interrupt, resume, step_skipped, step_started, step
#
# The Continuation handlers are defined unconditionally. On Rails < 8.1 those notifications are
# never emitted, so the extra methods are simply never invoked.
#
module RailsSemanticLogger
  module ActiveJob
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def enqueue(event)
        ex = enqueue_error(event)

        if ex
          log_with_formatter level: :error, event: event do |fmt|
            {
              message:   "Failed enqueuing #{fmt.job_info} (#{ex.class} (#{ex.message})",
              exception: ex
            }
          end
        elsif event.payload[:aborted]
          log_with_formatter level: :info, event: event do |fmt|
            {message: "Failed enqueuing #{fmt.job_info}, a before_enqueue callback halted the enqueuing execution."}
          end
        else
          log_with_formatter event: event do |fmt|
            {message: "Enqueued #{fmt.job_info}"}
          end
        end
      end

      def enqueue_at(event)
        ex = enqueue_error(event)

        if ex
          log_with_formatter level: :error, event: event do |fmt|
            {
              message:   "Failed enqueuing #{fmt.job_info} (#{ex.class} (#{ex.message})",
              exception: ex
            }
          end
        elsif event.payload[:aborted]
          log_with_formatter level: :info, event: event do |fmt|
            {message: "Failed enqueuing #{fmt.job_info}, a before_enqueue callback halted the enqueuing execution."}
          end
        else
          log_with_formatter event: event do |fmt|
            {message: "Enqueued #{fmt.job_info} at #{fmt.scheduled_at}"}
          end
        end
      end

      def perform_start(event)
        log_with_formatter event: event do |fmt|
          {message: "Performing #{fmt.job_info}"}
        end
      end

      def perform(event)
        ex = event.payload[:exception_object]
        if ex
          log_with_formatter event: event, log_duration: true, level: :error do |fmt|
            {
              message:   "Error performing #{fmt.job_info} in #{event.duration.round(2)}ms",
              exception: ex
            }
          end
        elsif event.payload[:aborted]
          log_with_formatter event: event, log_duration: true, level: :error do |fmt|
            {message: "Error performing #{fmt.job_info} in #{event.duration.round(2)}ms: " \
                      "a before_perform callback halted the job execution"}
          end
        else
          log_with_formatter event: event, log_duration: true do |fmt|
            {message: "Performed #{fmt.job_info} in #{event.duration.round(2)}ms"}
          end
        end
      end

      def enqueue_retry(event)
        ex   = event.payload[:error]
        wait = event.payload[:wait]

        log_with_formatter level: :info, event: event do |fmt|
          base    = "Retrying #{fmt.job_info} after #{fmt.executions} attempts in #{wait.to_i} seconds"
          message = ex ? "#{base}, due to a #{ex.class} (#{ex.message})." : "#{base}."

          {
            message:   message,
            exception: ex,
            payload:   {executions: fmt.executions, wait: wait.to_i}
          }
        end
      end

      def retry_stopped(event)
        ex = event.payload[:error]

        log_with_formatter level: :error, event: event do |fmt|
          {
            message:   "Stopped retrying #{fmt.job_info} due to a #{ex.class} (#{ex.message}), " \
                       "which reoccurred on #{fmt.executions} attempts.",
            exception: ex,
            payload:   {executions: fmt.executions}
          }
        end
      end

      def discard(event)
        ex = event.payload[:error]

        log_with_formatter level: :error, event: event do |fmt|
          {
            message:   "Discarded #{fmt.job_info} due to a #{ex.class} (#{ex.message}).",
            exception: ex
          }
        end
      end

      # ActiveJob Continuations (Rails 8.1+)

      def interrupt(event)
        description = event.payload[:description]
        reason      = event.payload[:reason]

        log_with_formatter level: :info, event: event do |fmt|
          {
            message: "Interrupted #{fmt.job_info} #{description} (#{reason})",
            payload: {description: description, reason: reason}
          }
        end
      end

      def resume(event)
        description = event.payload[:description]

        log_with_formatter level: :info, event: event do |fmt|
          {
            message: "Resuming #{fmt.job_info} #{description}",
            payload: {description: description}
          }
        end
      end

      def step_skipped(event)
        step = event.payload[:step]

        log_with_formatter level: :info, event: event do |fmt|
          {
            message: "Step '#{step.name}' skipped for #{fmt.job_info}",
            payload: {step_name: step.name}
          }
        end
      end

      def step_started(event)
        step = event.payload[:step]

        log_with_formatter level: :info, event: event do |fmt|
          message =
            if step.resumed?
              "Step '#{step.name}' resumed from cursor '#{step.cursor}' for #{fmt.job_info}"
            else
              "Step '#{step.name}' started for #{fmt.job_info}"
            end

          {
            message: message,
            payload: {step_name: step.name, step_cursor: step.cursor}
          }
        end
      end

      def step(event)
        step = event.payload[:step]
        ex   = event.payload[:exception_object]

        if event.payload[:interrupted]
          log_with_formatter level: :info, event: event, log_duration: true do |fmt|
            {
              message: "Step '#{step.name}' interrupted at cursor '#{step.cursor}' for " \
                       "#{fmt.job_info} in #{event.duration.round(2)}ms",
              payload: {step_name: step.name, step_cursor: step.cursor}
            }
          end
        elsif ex
          log_with_formatter level: :error, event: event, log_duration: true do |fmt|
            {
              message:   "Error during step '#{step.name}' at cursor '#{step.cursor}' for " \
                         "#{fmt.job_info} in #{event.duration.round(2)}ms: #{ex.class} (#{ex.message})",
              exception: ex,
              payload:   {step_name: step.name, step_cursor: step.cursor}
            }
          end
        else
          log_with_formatter level: :info, event: event, log_duration: true do |fmt|
            {
              message: "Step '#{step.name}' completed for #{fmt.job_info} in #{event.duration.round(2)}ms",
              payload: {step_name: step.name, step_cursor: step.cursor}
            }
          end
        end
      end

      def enqueue_all(event)
        jobs           = event.payload[:jobs]
        adapter        = event.payload[:adapter]
        enqueued_count = event.payload[:enqueued_count].to_i
        adapter_name   = ::ActiveJob.adapter_name(adapter)
        failed_count   = jobs.size - enqueued_count

        message =
          if failed_count.zero?
            enqueued_jobs_message(adapter_name, jobs)
          elsif jobs.any?(&:successfully_enqueued?)
            "#{enqueued_jobs_message(adapter_name, jobs.select(&:successfully_enqueued?))}. " \
              "Failed enqueuing #{failed_count} #{'job'.pluralize(failed_count)}"
          else
            "Failed enqueuing #{failed_count} #{'job'.pluralize(failed_count)} to #{adapter_name}"
          end

        logger.info(
          message: message,
          payload: {
            event_name:     event.name,
            adapter:        adapter_name,
            enqueued_count: enqueued_count,
            total_count:    jobs.size,
            job_classes:    jobs.map { |job| job.class.name }.tally
          }
        )
      end

      private

      # Upstream records an enqueue failure either via the event's exception_object or via
      # ActiveJob's job.enqueue_error. Prefer the former, fall back to the latter.
      def enqueue_error(event)
        event.payload[:exception_object] ||
          (event.payload[:job].respond_to?(:enqueue_error) ? event.payload[:job].enqueue_error : nil)
      end

      def enqueued_jobs_message(adapter_name, enqueued_jobs)
        enqueued_count     = enqueued_jobs.size
        job_classes_counts = enqueued_jobs.map(&:class).tally.sort_by { |_k, v| -v }
        "Enqueued #{enqueued_count} #{'job'.pluralize(enqueued_count)} to #{adapter_name} " \
          "(#{job_classes_counts.map { |klass, count| "#{count} #{klass}" }.join(', ')})"
      end

      class EventFormatter
        def initialize(event:, log_duration: false)
          @event = event
          @log_duration = log_duration
        end

        def job_info
          "#{job.class.name} (Job ID: #{job.job_id}) to #{queue_name}"
        end

        # Standard payload shared by every event. enqueued_at, scheduled_at, and duration are
        # only present when applicable (the job was scheduled, has been enqueued, or the event
        # carries a duration), so that handlers that do not have them never emit blank keys.
        def payload
          {}.tap do |h|
            h[:event_name]      = event.name
            h[:adapter]         = adapter_name
            h[:queue]           = job.queue_name
            h[:job_class]       = job.class.name
            h[:job_id]          = job.job_id
            h[:provider_job_id] = job.provider_job_id
            h[:enqueued_at]     = job.enqueued_at if job.respond_to?(:enqueued_at) && job.enqueued_at.present?
            h[:scheduled_at]    = scheduled_at if job.scheduled_at
            h[:duration]        = event.duration.round(2) if log_duration?
            h[:arguments]       = formatted_args
          end
        end

        def queue_name
          adapter_name + "(#{job.queue_name})"
        end

        def scheduled_at
          Time.at(job.scheduled_at).utc
        end

        def executions
          job.executions
        end

        private

        attr_reader :event

        def job
          event.payload[:job]
        end

        def adapter_name
          event.payload[:adapter].class.name.demodulize.remove("Adapter")
        end

        def formatted_args
          if defined?(job.class.log_arguments?) && !job.class.log_arguments?
            ""
          else
            JSON.pretty_generate(job.arguments.map { |arg| format(arg) })
          end
        end

        def format(arg)
          case arg
          when String
            arg.encode("UTF-8", invalid: :replace, undef: :replace)
          when Hash
            arg.transform_values { |value| format(value) }
          when Array
            arg.map { |value| format(value) }
          when GlobalID::Identification
            begin
              arg.to_global_id
            rescue StandardError
              arg
            end
          else
            arg
          end
        end

        def log_duration?
          @log_duration
        end
      end

      # Builds the structured log entry for an event. The block is given an EventFormatter and
      # returns a hash with :message, an optional :exception, and an optional :payload of extra
      # fields. Those extra fields are merged on top of the formatter's standard payload, so
      # handlers can add event-specific keys (executions, wait, step_name, ...) without each
      # having to rebuild the common job payload.
      def log_with_formatter(level: :info, **kw_args)
        fmt   = EventFormatter.new(**kw_args)
        msg   = yield fmt
        extra = msg.delete(:payload) || {}
        logger.public_send(level, **msg, payload: fmt.payload.merge(extra))
      end

      def logger
        ::ActiveJob::Base.logger
      end
    end
  end
end
