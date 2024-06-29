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
            action: "index",
            path:   "/path"
          }
        )

        messages = semantic_logger_events do
          subscriber.process_action(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :info,
          name:    "Rails",
          message: "Completed #index",
          payload: {
            action:      "index",
            path:        "/path",
            allocations: 0
          },
          metric:  "rails.controller.action"
        )
        assert messages[0].duration.is_a?(Float)
      end
    end
  end
end
