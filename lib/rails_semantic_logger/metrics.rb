module RailsSemanticLogger
  # The metrics that Rails Semantic Logger records for Rails, named after the OpenTelemetry semantic
  # conventions where one exists. They are recorded whatever is logged, and cost almost nothing until
  # the application adds a metric appender, such as `metric: :otlp`.
  #
  # Each recorder records its metrics through its component's logger, such as Rack's or Sidekiq's, as
  # Semantic Logger takes the name of the logger that records a metric as the metric's meter: one
  # meter for each component, never one for each controller or job class, which are dimensions.
  module Metrics
    autoload :ActionController, "rails_semantic_logger/metrics/action_controller"
    autoload :Subscriber, "rails_semantic_logger/metrics/subscriber"

    # Attaches the subscribers that record the metrics of each Rails component. Called once, by the
    # engine, unless `config.rails_semantic_logger.metrics` is false. Attaching to a component loads
    # none of it, so it is safe for a component the application does not use.
    def self.attach
      ActionController.attach_to(:action_controller)
    end

    # Returns [SemanticLogger::Logger] the logger that records the metrics. A metric does not depend
    # on the name of the logger that records it.
    def self.logger
      @logger ||= SemanticLogger["RailsSemanticLogger::Metrics"]
    end
  end
end
