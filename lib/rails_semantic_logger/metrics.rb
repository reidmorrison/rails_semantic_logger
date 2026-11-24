module RailsSemanticLogger
  # The metrics that Rails Semantic Logger records for Rails, named after the OpenTelemetry semantic
  # conventions where one exists. They are recorded whatever is logged, and cost almost nothing until
  # the application adds a metric appender, such as `metric: :otlp`.
  module Metrics
    # Returns [SemanticLogger::Logger] the logger that records the metrics. A metric does not depend
    # on the name of the logger that records it.
    def self.logger
      @logger ||= SemanticLogger["RailsSemanticLogger::Metrics"]
    end
  end
end
