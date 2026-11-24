module RailsSemanticLogger
  module Metrics
    # Records how long each Solid Queue operation takes, as `solid_queue.operation.duration`, by the
    # operation, the event that Solid Queue instruments, such as `claim` or `start_process`. Solid
    # Queue is a system of its own and no OpenTelemetry convention covers its operations, so it is
    # named under `solid_queue`. The jobs it runs are recorded by Active Job's metrics.
    class SolidQueue < Subscriber
      NAME = "solid_queue.operation.duration".freeze

      # The events that Solid Queue instruments, each "<event>.solid_queue".
      EVENTS = %w[
        dispatch_scheduled claim release_many_claimed fail_many_claimed release_claimed retry_all retry
        discard_all discard release_many_blocked release_blocked enqueue_recurring_task start_process
        shutdown_process register_process deregister_process prune_processes thread_error
        graceful_termination immediate_termination unhandled_signal_error replace_fork
      ].freeze

      EVENTS.each do |operation|
        define_method(operation) { |event| record(operation, event) }
      end

      private

      def record(operation, event)
        dimensions = {"solid_queue.operation.name" => operation}
        error_type = error_type(event.payload)
        dimensions["error.type"] = error_type if error_type
        time(NAME, event, dimensions)
      end

      # The class of the exception that the operation raised, or that it reports, as thread_error does.
      def error_type(payload)
        return payload[:exception].first if payload[:exception]

        payload[:error].class.name if payload[:error].is_a?(Exception)
      end
    end
  end
end
