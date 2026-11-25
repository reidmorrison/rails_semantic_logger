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
    autoload :SolidQueue, "rails_semantic_logger/metrics/solid_queue"
    autoload :Subscriber, "rails_semantic_logger/metrics/subscriber"

    # The subscribers that record the metrics of each Rails component, by the namespace of the events
    # they attach to.
    SUBSCRIBERS = {
      "ActionController" => :action_controller,
      "ActionView"       => :action_view,
      "ActiveRecord"     => :active_record,
      "ActiveJob"        => :active_job,
      "ActionMailer"     => :action_mailer,
      "Cache"            => :active_support,
      "SolidQueue"       => :solid_queue
    }.freeze

    # Attaches the subscribers that record the metrics of each Rails component. Called once, by the
    # engine, unless `config.rails_semantic_logger.metrics` is false. Attaching to a component loads
    # none of it, so it is safe for a component the application does not use.
    #
    # solid_queue: whether to record Solid Queue's metrics, which are recorded through its logger, a
    # Semantic Logger one only while Rails Semantic Logger replaces it, as the Sidekiq job metrics are
    # recorded only while Sidekiq's is.
    def self.attach(solid_queue: true)
      subscribers = solid_queue ? SUBSCRIBERS : SUBSCRIBERS.except("SolidQueue")
      subscribers.each { |subscriber, namespace| const_get(subscriber).attach_to(namespace) }
    end

    # Returns [Array<Class>] the recorders of the Rails metrics, each of which names the dimension keys
    # it records: the subscribers, the request middleware and the Sidekiq job logger.
    def self.recorders
      [
        RailsSemanticLogger::Rack::Metrics,
        *SUBSCRIBERS.keys.map { |subscriber| const_get(subscriber) },
        RailsSemanticLogger::Sidekiq::JobLogger
      ]
    end

    # Declares the dimension keys of the Rails metrics safe from SemanticLogger.sensitive_keys, which
    # Rails Semantic Logger fills from config.filter_parameters, and which match keys by substring: an
    # application that filters :name or :type would otherwise redact messaging.destination.name and
    # error.type, merging every series of a metric into one. Called by the engine before it creates the
    # appenders, since a metric appender keeps the redaction of what it already holds.
    def self.declare_dimension_keys
      SemanticLogger.safe_dimension_keys |= dimension_keys
    end

    # Returns [Array<String>] the dimension keys that the Rails metrics record.
    def self.dimension_keys
      recorders.flat_map { |recorder| recorder::DIMENSION_KEYS }.uniq
    end
  end
end
