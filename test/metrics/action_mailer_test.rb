require_relative "../test_helper"

module Metrics
  class ActionMailerTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::ActionMailer do
      let(:subscriber) { RailsSemanticLogger::Metrics::ActionMailer.new }

      def record(name, payload)
        event = ActiveSupport::Notifications::Event.new("#{name}.action_mailer", 5.seconds.ago, Time.zone.now, "1",
                                                        payload)
        semantic_logger_metrics { subscriber.public_send(name, event) }
      end

      it "records how long a delivery took, by mailer" do
        metric = assert_metric(
          record(:deliver, mailer: "UserMailer", perform_deliveries: true),
          name:       "rails.action_mailer.delivery.duration",
          kind:       :histogram,
          unit:       "s",
          dimensions: {"rails.action_mailer.mailer" => "UserMailer"}
        )

        assert_in_delta 5, metric.value, 0.5
      end

      it "records the error.type of a delivery that raised" do
        assert_metric(
          record(:deliver, mailer: "UserMailer", exception_object: Net::ReadTimeout.new),
          name:       "rails.action_mailer.delivery.duration",
          dimensions: {"rails.action_mailer.mailer" => "UserMailer", "error.type" => "Net::ReadTimeout"}
        )
      end

      it "records nothing for a delivery skipped by perform_deliveries" do
        assert_empty record(:deliver, mailer: "UserMailer", perform_deliveries: false)
      end

      it "records how long building a mail took, by mailer action" do
        assert_metric(
          record(:process, mailer: "UserMailer", action: :welcome),
          name:       "rails.action_mailer.process.duration",
          kind:       :histogram,
          dimensions: {"code.function.name" => "UserMailer#welcome"}
        )
      end
    end
  end
end
