require "active_support/subscriber"

module RailsSemanticLogger
  module Metrics
    # Base for the subscribers that turn ActiveSupport::Notifications events into metrics. Each
    # subclass owns the metrics of one Rails component: which events it records, their names, and
    # their dimensions. It records them whatever is logged, apart from the log subscribers.
    #
    # Each subclass names, as LOGGER_NAME, the logger of its component, through which it records them:
    # the name of the logger that records a metric is its meter.
    class Subscriber < ::ActiveSupport::Subscriber
      # Returns [SemanticLogger::Logger] the logger that records the component's metrics. Found by its
      # name, rather than as the component's logger, which an application can replace with one that
      # records no metrics, or with nil to log nothing.
      def self.logger
        @logger ||= SemanticLogger[self::LOGGER_NAME]
      end

      # Refuses, at boot, a subscriber that names no logger, which would otherwise record nothing,
      # reporting it only once, on its first event: finding its logger raises a NameError.
      def self.attach_to(...)
        logger
        super
      end

      # Whether Active Support may leave this subscriber out of the event `name`: while no metric
      # appender collects the metrics. Asked by ActiveSupport::Notifications each time an event starts,
      # so that, once every other listener is silenced too, as a log subscriber is below its level, it
      # does not build the event at all, nor time it. Never raises, as it is asked from the code that
      # it instruments: when the answer is not known, it listens, and #call decides.
      def silenced?(_name)
        !self.class.logger.collecting_metrics?
      rescue StandardError
        false
      end

      # Active Support raises a subscriber's exception in the code that it instruments, so a metric
      # that fails would fail the request, the query, or the job. It is reported once instead.
      #
      # Records nothing, without reading the event, while no metric appender collects the metrics: one
      # that started before the last metric appender was removed.
      def call(event)
        super if self.class.logger.collecting_metrics?
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
        record_duration(name, event.duration, dimensions)
      end

      # Records a duration given in milliseconds, in seconds, in the histogram `name`.
      def record_duration(name, duration_ms, dimensions = nil)
        self.class.logger.time(name, duration: duration_ms, dimensions: dimensions)
      end

      # OpenTelemetry's error.type for an exception: its class, or "_OTHER" for an anonymous class,
      # which has no name.
      def error_type(exception)
        exception.class.name || "_OTHER"
      end

      # Adds `amount`, one by default, to the counter `name`, of what is counted in `unit`, in the
      # notation of OpenTelemetry (UCUM), such as "{redirect}".
      def increment(name, unit, dimensions = nil, amount = 1)
        self.class.logger.increment(name, amount, unit: unit, dimensions: dimensions)
      end
    end
  end
end
