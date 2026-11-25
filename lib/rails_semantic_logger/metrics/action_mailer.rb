module RailsSemanticLogger
  module Metrics
    # Records the metrics of Action Mailer. No OpenTelemetry convention covers email, so they are
    # named under `rails.action_mailer`.
    class ActionMailer < Subscriber
      # The logger of Action Mailer, whose name is the meter of its metrics.
      LOGGER_NAME = "ActionMailer::Base".freeze

      # How long delivering a mail took. A mail skipped because perform_deliveries is false was not
      # delivered, so it is not recorded.
      def deliver(event)
        payload = event.payload
        error   = payload[:exception_object]
        return unless payload[:perform_deliveries] || error

        dimensions = {}
        dimensions["rails.action_mailer.mailer"] = payload[:mailer].to_s if payload[:mailer]
        dimensions["error.type"]                 = error_type(error) if error
        time("rails.action_mailer.delivery.duration", event, dimensions)
      end

      # How long building a mail took, by its mailer action, such as "UserMailer#welcome".
      # An anonymous mailer has no name, so it is recorded without one.
      def process(event)
        payload    = event.payload
        dimensions = {}
        if payload[:mailer] && payload[:action]
          dimensions["code.function.name"] = "#{payload[:mailer]}##{payload[:action]}"
        end
        error = payload[:exception_object]
        dimensions["error.type"] = error_type(error) if error
        time("rails.action_mailer.process.duration", event, dimensions)
      end
    end
  end
end
