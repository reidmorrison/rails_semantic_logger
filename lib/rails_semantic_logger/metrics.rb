module RailsSemanticLogger
  # The metrics that Rails Semantic Logger records for Rails, named after the OpenTelemetry semantic
  # conventions where one exists. They are recorded whatever is logged, and cost almost nothing until
  # the application adds a metric appender, such as `metric: :otlp`.
  #
  # Each recorder records its metrics through its component's logger, such as Rack's or Sidekiq's, as
  # Semantic Logger takes the name of the logger that records a metric as the metric's meter: one
  # meter for each component, never one for each controller or job class, which are dimensions.
  module Metrics
  end
end
