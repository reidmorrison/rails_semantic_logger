module RailsSemanticLogger
  module Metrics
    # Records how long each Solid Queue operation takes, as `solid_queue.operation.duration`, by the
    # operation, the event that Solid Queue instruments, such as `claim` or `start_process`. Solid
    # Queue is a system of its own and no OpenTelemetry convention covers its operations, so it is
    # named under `solid_queue`. The jobs it runs are recorded by Active Job's metrics.
    class SolidQueue < Subscriber
      # The logger of Solid Queue, whose name is the meter of its metrics.
      def self.logger
        ::SolidQueue.logger
      end

      # The dimensions it records, which no sensitive key redacts (see Metrics.declare_dimension_keys).
      DIMENSION_KEYS = %w[solid_queue.operation.name error.type].freeze

      NAME = "solid_queue.operation.duration".freeze

      # The events that Solid Queue instruments, each "<event>.solid_queue".
      EVENTS = %w[
        dispatch_scheduled claim polling release_many_claimed fail_many_claimed release_claimed retry_all
        retry discard_all discard release_many_blocked release_blocked enqueue_recurring_task
        start_process shutdown_process register_process deregister_process prune_processes thread_error
        replace_thread graceful_termination immediate_termination unhandled_signal_error replace_fork
        fork_boot_timeout finish_batch sweep_stalled_batches batch_progress_error
      ].freeze

      EVENTS.each do |operation|
        define_method(operation) { |event| record(operation, event) }
      end

      private

      def record(operation, event)
        dimensions = {"solid_queue.operation.name" => operation}
        failure = failure_type(operation, event.payload)
        dimensions["error.type"] = failure if failure
        time(NAME, event, dimensions)
      end

      # The class of the exception that the operation raised, or that it reports, as thread_error does.
      # A recurring task that failed to enqueue its job reports only the message, as enqueue_error. The
      # error of fail_many_claimed is why the claimed jobs failed, not a failure of the operation.
      def failure_type(operation, payload)
        raised = raised_error_type(payload)
        return raised if raised
        return error_type(payload[:error]) if payload[:error].is_a?(Exception) && operation != "fail_many_claimed"

        "enqueue_error" if payload[:enqueue_error]
      end
    end
  end
end
