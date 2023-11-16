require_relative "../test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  describe DashboardController do
    describe "#show" do
      it "has no errors" do
        get dashboard_url

        assert_response :success
      end

      it "logs message" do
        messages = semantic_logger_events do
          get dashboard_url
        end
        assert_equal 3, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:   :debug,
          name:    "Rack",
          message: "Started",
          payload: {
            method: "GET",
            path:   "/dashboard",
            ip:     "127.0.0.1"
          }
        )

        assert_semantic_logger_event(
          messages[1],
          level:   :debug,
          name:    "Rails",
          message: "Processing #show",
          payload: nil
        )

        assert_semantic_logger_event(
          messages[2],
          level:            :info,
          name:             "Rails",
          message:          "Completed #show",
          payload_includes: {
            controller:     "DashboardController",
            action:         "show",
            format:         "HTML",
            method:         "GET",
            path:           "/dashboard",
            status:         200,
            status_message: "OK"
          }
        )
      end

      it "does not break rails notifications" do
        PayloadCollector.wrap do
          get dashboard_url
        end

        payload = PayloadCollector.last
        assert_equal payload[:params], {"controller" => "dashboard", "action" => "show"}
      end
    end
  end
end
