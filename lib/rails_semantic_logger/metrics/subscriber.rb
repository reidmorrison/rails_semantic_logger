require "active_support/subscriber"

module RailsSemanticLogger
  module Metrics
    # Base for the subscribers that turn ActiveSupport::Notifications events into metrics. Each
    # subclass owns the metrics of one Rails component: which events it records, their names, and
    # their dimensions. It records them whatever is logged, apart from the log subscribers.
    class Subscriber < ::ActiveSupport::Subscriber
      # Active Support raises a subscriber's exception in the code that it instruments, so a metric
      # that fails would fail the request, the query, or the job. It is reported once instead.
      def call(event)
        super
      rescue StandardError => e
        report(e)
      end

      private

      def report(exception)
        return if @reported

        @reported = true
        SemanticLogger::Processor.logger.warn(
          "#{self.class.name} failed to record a metric. Further failures are not reported.", exception
        )
      rescue StandardError
        nil
      end

      # Records the duration of the event, in seconds, in the histogram `name`.
      def time(name, event, dimensions = nil)
        RailsSemanticLogger::Metrics.logger.time(name, duration: event.duration, dimensions: dimensions)
      end

      # OpenTelemetry's error.type for an exception: its class, or "_OTHER" for an anonymous class,
      # which has no name.
      def error_type(exception)
        exception.class.name || "_OTHER"
      end

      # Adds one to the counter `name`.
      def increment(name, dimensions = nil)
        RailsSemanticLogger::Metrics.logger.increment(name, dimensions: dimensions)
      end
    end
  end
end
