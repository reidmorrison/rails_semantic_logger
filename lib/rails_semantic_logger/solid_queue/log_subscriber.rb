module RailsSemanticLogger
  module SolidQueue
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def dispatch_scheduled(event)
        log_event(event, :debug, "Dispatch scheduled jobs", **event.payload.slice(:batch_size, :size))
      end

      def claim(event)
        log_event(event, :debug, "Claim jobs", **event.payload.slice(:process_id, :job_ids, :claimed_job_ids, :size))
      end

      def release_many_claimed(event)
        log_event(event, :info, "Release claimed jobs", **event.payload.slice(:size))
      end

      def fail_many_claimed(event)
        log_event(event, :warn, "Fail claimed jobs", **event.payload.slice(:job_ids, :process_ids))
      end

      def release_claimed(event)
        log_event(event, :info, "Release claimed job", **event.payload.slice(:job_id, :process_id))
      end

      def retry_all(event)
        log_event(event, :debug, "Retry failed jobs", **event.payload.slice(:jobs_size, :size))
      end

      def retry(event)
        log_event(event, :debug, "Retry failed job", **event.payload.slice(:job_id))
      end

      def discard_all(event)
        log_event(event, :debug, "Discard jobs", **event.payload.slice(:jobs_size, :size, :status))
      end

      def discard(event)
        log_event(event, :debug, "Discard job", **event.payload.slice(:job_id, :status))
      end

      def release_many_blocked(event)
        log_event(event, :debug, "Unblock jobs", **event.payload.slice(:limit, :size))
      end

      def release_blocked(event)
        log_event(event, :debug, "Release blocked job", **event.payload.slice(:job_id, :concurrency_key, :released))
      end

      def enqueue_recurring_task(event)
        attributes      = event.payload.slice(:task, :active_job_id, :enqueue_error)
        attributes[:at] = event.payload[:at]&.iso8601

        if attributes[:active_job_id].nil? && event.payload[:skipped].nil?
          log_event(event, :error, "Error enqueuing recurring task", **attributes)
        elsif event.payload[:other_adapter]
          log_event(event, :debug, "Enqueued recurring task outside Solid Queue", **attributes)
        else
          action = event.payload[:skipped].present? ? "Skipped recurring task – already dispatched" : "Enqueued recurring task"
          log_event(event, :debug, action, **attributes)
        end
      end

      def start_process(event)
        process    = event.payload[:process]
        attributes = process_attributes(process).merge(process.metadata)

        log_event(event, :info, "Started #{process.kind}", **attributes)
      end

      def shutdown_process(event)
        process    = event.payload[:process]
        attributes = process_attributes(process).merge(process.metadata)

        log_event(event, :info, "Shutdown #{process.kind}", **attributes)
      end

      def register_process(event)
        process_kind = event.payload[:kind]
        attributes   = event.payload.slice(:pid, :hostname, :process_id, :name)

        if (error = event.payload[:error])
          log_event(event, :warn, "Error registering #{process_kind}", exception: error, **attributes)
        else
          log_event(event, :debug, "Register #{process_kind}", **attributes)
        end
      end

      def deregister_process(event)
        process    = event.payload[:process]
        attributes = {
          process_id:        process.id,
          pid:               process.pid,
          hostname:          process.hostname,
          name:              process.name,
          last_heartbeat_at: process.last_heartbeat_at.iso8601,
          claimed_size:      event.payload[:claimed_size],
          pruned:            event.payload[:pruned]
        }

        if (error = event.payload[:error])
          log_event(event, :warn, "Error deregistering #{process.kind}", exception: error, **attributes)
        else
          log_event(event, :debug, "Deregister #{process.kind}", **attributes)
        end
      end

      def prune_processes(event)
        log_event(event, :debug, "Prune dead processes", **event.payload.slice(:size))
      end

      def thread_error(event)
        log_event(event, :error, "Error in thread", exception: event.payload[:error])
      end

      def graceful_termination(event)
        attributes = event.payload.slice(:process_id, :supervisor_pid, :supervised_processes)

        if event.payload[:shutdown_timeout_exceeded]
          log_event(event, :warn, "Supervisor wasn't terminated gracefully - shutdown timeout exceeded", **attributes)
        else
          log_event(event, :info, "Supervisor terminated gracefully", **attributes)
        end
      end

      def immediate_termination(event)
        log_event(event, :info, "Supervisor terminated immediately",
                  **event.payload.slice(:process_id, :supervisor_pid, :supervised_processes))
      end

      def unhandled_signal_error(event)
        log_event(event, :error, "Received unhandled signal", **event.payload.slice(:signal))
      end

      def replace_fork(event)
        supervisor_pid = event.payload[:supervisor_pid]
        status         = event.payload[:status]
        attributes     = event.payload.slice(:pid).merge(
          status:          status.exitstatus || "no exit status set",
          pid_from_status: status.pid,
          signaled:        status.signaled?,
          stopsig:         status.stopsig,
          termsig:         status.termsig
        )

        if (replaced_fork = event.payload[:fork])
          log_event(event, :info, "Replaced terminated #{replaced_fork.kind}",
                    **attributes, hostname: replaced_fork.hostname, name: replaced_fork.name)
        elsif supervisor_pid != 1 # Running Docker, possibly having some processes that have been reparented
          log_event(event, :warn, "Tried to replace forked process but it had already died", **attributes)
        end
      end

      private

      def process_attributes(process)
        {
          pid:        process.pid,
          hostname:   process.hostname,
          process_id: process.process_id,
          name:       process.name
        }
      end

      def log_event(event, level, action, exception: nil, **attributes)
        logger.public_send(level) do
          msg = {message: action, payload: attributes, duration: event.duration}
          msg[:exception] = exception if exception
          msg
        end
      end

      def logger
        @logger ||= SemanticLogger["SolidQueue"]
      end
    end
  end
end
