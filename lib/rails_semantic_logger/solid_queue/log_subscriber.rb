module RailsSemanticLogger
  module SolidQueue
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      include RailsSemanticLogger::SilencedBelowLevel

      # The highest level at which each event can be logged, such as :warn for a process that failed
      # to register, though it is logged at :debug otherwise.
      LOG_LEVELS = {
        "dispatch_scheduled.solid_queue"     => :debug,
        "claim.solid_queue"                  => :debug,
        "release_many_claimed.solid_queue"   => :info,
        "fail_many_claimed.solid_queue"      => :warn,
        "release_claimed.solid_queue"        => :info,
        "retry_all.solid_queue"              => :debug,
        "retry.solid_queue"                  => :debug,
        "discard_all.solid_queue"            => :debug,
        "discard.solid_queue"                => :debug,
        "release_many_blocked.solid_queue"   => :debug,
        "release_blocked.solid_queue"        => :debug,
        "enqueue_recurring_task.solid_queue" => :error,
        "start_process.solid_queue"          => :info,
        "shutdown_process.solid_queue"       => :info,
        "register_process.solid_queue"       => :warn,
        "deregister_process.solid_queue"     => :warn,
        "prune_processes.solid_queue"        => :debug,
        "thread_error.solid_queue"           => :error,
        "graceful_termination.solid_queue"   => :warn,
        "immediate_termination.solid_queue"  => :info,
        "unhandled_signal_error.solid_queue" => :error,
        "replace_fork.solid_queue"           => :warn
      }.freeze

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
        log_event(event, :warn, "Fail claimed jobs", exception: event.payload[:error],
                                                     **event.payload.slice(:job_ids, :process_ids))
      end

      # Solid Queue 1.7+ batches.
      # Solid Queue logs this event at info even when finishing the batch raised. Log that at error,
      # with the exception, so a failed finish does not look like a successful one.
      def finish_batch(event)
        attributes = event.payload.slice(:batch_id, :total_jobs, :completed_jobs, :failed_jobs)
        if (exception = event.payload[:exception_object])
          log_event(event, :error, "Error finishing batch", exception: exception, **attributes)
        else
          log_event(event, :info, "Finish batch", **attributes)
        end
      end

      def sweep_stalled_batches(event)
        log_event(event, :debug, "Sweep stalled batches",
                  **event.payload.slice(:stale_executions, :finished_batches, :started_batches))
      end

      def batch_progress_error(event)
        log_event(event, :error, "Error updating batch progress", exception: event.payload[:error],
                                                                  **event.payload.slice(:batch_id, :job_id))
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
        log_event(event, :debug, "Release blocked job",
                  **event.payload.slice(:job_id, :concurrency_key, :released, :failed))
      end

      def enqueue_recurring_task(event)
        attributes      = event.payload.slice(:task, :active_job_id, :enqueue_error)
        attributes[:at] = event.payload[:at]&.iso8601

        if attributes[:active_job_id].nil? && event.payload[:skipped].nil?
          log_event(event, :error, "Error enqueuing recurring task", **attributes)
        elsif event.payload[:other_adapter]
          log_event(event, :debug, "Enqueued recurring task outside Solid Queue", **attributes)
        else
          action = if event.payload[:skipped].present?
                     "Skipped recurring task – already dispatched"
                   else
                     "Enqueued recurring task"
                   end
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

      # Solid Queue 1.5.1+.
      def fork_boot_timeout(event)
        process    = event.payload[:process]
        attributes = event.payload.slice(:pid).merge(hostname: process.hostname, name: process.name)
        if (exception = event.payload[:exception_object])
          log_event(event, :error, "Error terminating #{process.kind} that failed to boot in time",
                    exception: exception, **attributes)
        else
          log_event(event, :warn, "Terminate #{process.kind} that failed to boot in time", **attributes)
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

      # Solid Queue's own processes log these events, with no application code on the stack, so they
      # record no call site rather than one inside Solid Queue.
      def log_event(event, level, action, exception: nil, **attributes)
        logger.public_send(level, call_site: false) do
          msg = {message: action, payload: attributes, duration: event.duration}
          msg[:exception] = exception if exception
          msg
        end
      end

      # Solid Queue's logger, which the engine makes a Semantic Logger one, so that the level that an
      # application sets on it applies here too, as it does to Solid Queue's own log entries.
      def logger
        ::SolidQueue.logger
      end

      def log_level_of(name)
        LOG_LEVELS[name]
      end
    end
  end
end
