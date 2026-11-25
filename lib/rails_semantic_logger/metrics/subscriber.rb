require "active_support/subscriber"

module RailsSemanticLogger
  module Metrics
    # Base for the subscribers that turn ActiveSupport::Notifications events into metrics. Each
    # subclass owns the metrics of one Rails component: which events it records, their names, and
    # their dimensions. It records them whatever is logged, apart from the log subscribers.
    #
    # Each subclass records them through the logger of its component (.logger), the instance that the
    # engine gave the component and through which its log entries are logged: the name of the logger
    # that records a metric is its meter. A metric is recorded whatever the logger's level.
    class Subscriber < ::ActiveSupport::Subscriber
      # Returns [SemanticLogger::Logger] the logger of the component, through which its metrics are
      # recorded, such as ActiveRecord::Base.logger. Each subclass gives its own, read on each event
      # rather than kept, as the engine may give the component its logger after it has attached.
      def self.logger
        raise NotImplementedError, "#{name} must define self.logger, the logger of its component"
      end

      # Refuses, at boot, a subscriber that gives no logger, which would otherwise record nothing,
      # reporting it only once, on its first event. Asks no logger, as finding one can load the
      # component before the application has initialized.
      def self.attach_to(...)
        if method(:logger).owner == Subscriber.singleton_class
          raise NotImplementedError,
                "#{name} must define self.logger"
        end

        super
      end

      # Whether Active Support may leave this subscriber out of the event `name`: while no metric
      # appender collects the metrics. Asked by ActiveSupport::Notifications each time an event starts,
      # so that the event is built for it only while its metrics are collected. Active Support skips
      # the event only when every one of its listeners is silenced, as Rails' log subscribers are
      # below their level; a listener that cannot be silenced, such as the one that adds up Active
      # Record's runtime, still times it. Never raises, as it is asked from the code that it
      # instruments: when the answer is not known, it listens, and #call decides.
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
        SemanticLogger.internal_logger.warn(
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

      # OpenTelemetry's error.type for an exception: its class's name (see #class_name).
      def error_type(exception)
        class_name(exception.class)
      end

      # A class as a dimension: its name, or "_OTHER", OpenTelemetry's value for an unknown
      # error.type, for an anonymous class, which has none.
      def class_name(klass)
        klass.name || "_OTHER"
      end

      # The error.type of an event whose block raised, from the exception that Active Support adds to
      # its payload, or nil when it did not raise. A payload that names the exception's class only,
      # as :exception, is named by it, or "_OTHER" when the class has no name.
      def raised_error_type(payload)
        exception = payload[:exception_object]
        return error_type(exception) if exception

        payload[:exception] && (payload[:exception].first || "_OTHER")
      end

      # Adds `amount`, one by default, to the counter `name`, of what is counted in `unit`, in the
      # notation of OpenTelemetry (UCUM), such as "{redirect}".
      def increment(name, unit, dimensions = nil, amount = 1)
        self.class.logger.increment(name, amount, unit: unit, dimensions: dimensions)
      end
    end
  end
end
