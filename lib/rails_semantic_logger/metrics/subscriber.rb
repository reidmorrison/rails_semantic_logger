require "active_support/subscriber"

module RailsSemanticLogger
  module Metrics
    # Base for the subscribers that turn ActiveSupport::Notifications events into metrics. Each
    # subclass owns the metrics of one Rails component: which events it records, their names, and
    # their dimensions. It records them whatever is logged, apart from the log subscribers.
    class Subscriber < ::ActiveSupport::Subscriber
      private

      # Records the duration of the event, in seconds, in the histogram `name`.
      def time(name, event, dimensions = nil)
        RailsSemanticLogger::Metrics.logger.time(name, duration: event.duration, dimensions: dimensions)
      end

      # Adds one to the counter `name`.
      def increment(name, dimensions = nil)
        RailsSemanticLogger::Metrics.logger.increment(name, dimensions: dimensions)
      end
    end
  end
end
