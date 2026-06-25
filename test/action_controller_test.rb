require_relative "test_helper"

class ActionControllerTest < Minitest::Test
  describe "RailsSemanticLogger::ActionController::LogSubscriber" do
    let(:subscriber) { RailsSemanticLogger::ActionController::LogSubscriber.new }

    describe "#process_action" do
      it "does not fail if params is not a Hash nor an instance of ActionController::Parameters" do
        event = ActiveSupport::Notifications::Event.new(
          "start_processing.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {
            payload: "{}"
          }
        )

        messages = semantic_logger_events do
          subscriber.process_action(event)
        end

        assert_equal 1, messages.count, messages
      end

      it "includes cpu_time and idle_time in the payload" do
        event = ActiveSupport::Notifications::Event.new(
          "process_action.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {
            controller: "ArticlesController",
            action:     "index",
            status:     200
          }
        )

        messages = semantic_logger_events do
          subscriber.process_action(event)
        end

        assert_equal 1, messages.count, messages
        payload = messages[0].payload

        assert_instance_of Float, payload[:cpu_time]
        assert_instance_of Float, payload[:idle_time]
      end
    end
  end
end
