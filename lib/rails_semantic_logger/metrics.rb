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
    autoload :ActionMailer, "rails_semantic_logger/metrics/action_mailer"
    autoload :ActionView, "rails_semantic_logger/metrics/action_view"
    autoload :ActiveJob, "rails_semantic_logger/metrics/active_job"
    autoload :ActiveRecord, "rails_semantic_logger/metrics/active_record"
    autoload :Cache, "rails_semantic_logger/metrics/cache"
    autoload :Subscriber, "rails_semantic_logger/metrics/subscriber"

    # Attaches the subscribers that record the metrics of each Rails component. Called once, by the
    # engine, unless `config.rails_semantic_logger.metrics` is false. Attaching to a component loads
    # none of it, so it is safe for a component the application does not use.
    def self.attach
      ActionController.attach_to(:action_controller)
      ActionView.attach_to(:action_view)
      ActiveRecord.attach_to(:active_record)
      ActiveJob.attach_to(:active_job)
      ActionMailer.attach_to(:action_mailer)
      Cache.attach_to(:active_support)
    end
  end
end
