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

      it "emits the rails.controller.process_action metric" do
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
        assert_equal "rails.controller.process_action", messages[0].metric
      end
    end

    describe "#redirect_to" do
      it "emits the rails.controller.redirect_to metric" do
        event = ActiveSupport::Notifications::Event.new(
          "redirect_to.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://example.com/", request: nil}
        )

        messages = semantic_logger_events do
          subscriber.redirect_to(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :info,
          message: "Redirected to",
          metric:  "rails.controller.redirect_to"
        )
      end
    end

    describe "#start_processing" do
      let(:event) do
        ActiveSupport::Notifications::Event.new(
          "start_processing.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {
            controller: "ArticlesController",
            action:     "index"
          }
        )
      end

      after do
        # Restore the default so the option does not leak into other tests.
        RailsSemanticLogger::ActionController::LogSubscriber.processing_log_level = :debug
      end

      it "logs the Processing message at :debug by default" do
        RailsSemanticLogger::ActionController::LogSubscriber.processing_log_level = :debug

        messages = semantic_logger_events do
          subscriber.start_processing(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :debug,
          message: "Processing #index"
        )
      end

      it "logs the Processing message at :info when processing_log_level is :info" do
        RailsSemanticLogger::ActionController::LogSubscriber.processing_log_level = :info

        messages = semantic_logger_events do
          subscriber.start_processing(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :info,
          message: "Processing #index"
        )
      end
    end
  end
end
