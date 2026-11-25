require_relative "../test_helper"

module Metrics
  class ActionControllerTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::ActionController do
      let(:subscriber) { RailsSemanticLogger::Metrics::ActionController.new }

      it "records through the logger of Action Controller, whose name is the meter" do
        assert_equal "ActionController::Base", RailsSemanticLogger::Metrics::ActionController.logger.name
      end

      def event(name, payload)
        ActiveSupport::Notifications::Event.new("#{name}.action_controller", 5.seconds.ago, Time.zone.now,
                                                SecureRandom.uuid, payload)
      end

      def record(name, payload)
        semantic_logger_metrics { subscriber.public_send(name, event(name, payload)) }
      end

      describe "#process_action" do
        it "records the action's duration with the controller and action" do
          metrics = record(:process_action, controller: "ArticlesController", action: "index", status: 200)

          metric = assert_metric(
            metrics,
            name:       "rails.action_controller.process_action.duration",
            kind:       :histogram,
            unit:       "s",
            dimensions: {"code.function.name" => "ArticlesController#index", "http.response.status_code" => 200}
          )

          assert_in_delta 5, metric.value, 0.5
        end

        it "records the exception class and the status Rails renders for it" do
          # Rails sets the status that it renders for the exception before it instruments the event.
          metrics = record(
            :process_action,
            controller: "ArticlesController",
            action:     "show",
            status:     404,
            exception:  ["ActiveRecord::RecordNotFound", "not found"]
          )

          assert_metric(
            metrics,
            name:       "rails.action_controller.process_action.duration",
            dimensions: {
              "code.function.name"        => "ArticlesController#show",
              "http.response.status_code" => 404,
              "error.type"                => "ActiveRecord::RecordNotFound"
            }
          )
        end
      end

      describe "#halted_callback" do
        it "counts it by the name of a method callback" do
          assert_metric(
            record(:halted_callback, filter: :authenticate),
            name:       "rails.action_controller.halted_callbacks",
            kind:       :counter,
            value:      1,
            dimensions: {"rails.action_controller.filter" => "authenticate"}
          )
        end

        it "counts it by the class of any other callback" do
          assert_metric(
            record(:halted_callback, filter: -> {}),
            name:       "rails.action_controller.halted_callbacks",
            dimensions: {"rails.action_controller.filter" => "Proc"}
          )
        end
      end

      it "counts a rescue_from by the exception class" do
        assert_metric(
          record(:rescue_from_callback, exception: ArgumentError.new("boom")),
          name:       "rails.action_controller.rescued_exceptions",
          kind:       :counter,
          dimensions: {"error.type" => "ArgumentError"}
        )
      end

      it "counts a redirect by its status" do
        assert_metric(
          record(:redirect_to, status: 302, location: "https://example.com/", request: nil),
          name:       "rails.action_controller.redirects",
          kind:       :counter,
          unit:       "{redirect}",
          dimensions: {"http.response.status_code" => 302}
        )
      end

      it "counts open and path relative redirects by kind" do
        assert_metric(
          record(:open_redirect, location: "https://elsewhere.example.com/"),
          name:       "rails.action_controller.unsafe_redirects",
          dimensions: {"rails.action_controller.redirect.kind" => "open"}
        )
        assert_metric(
          record(:unsafe_redirect, url: "foo"),
          name:       "rails.action_controller.unsafe_redirects",
          dimensions: {"rails.action_controller.redirect.kind" => "path_relative"}
        )
      end

      it "times sent files and data" do
        assert_metric(record(:send_file, path: "/tmp/x"), name: "rails.action_controller.send_file.duration",
                                                          kind: :histogram)
        assert_metric(record(:send_data, filename: "x"), name: "rails.action_controller.send_data.duration",
                                                         kind: :histogram)
      end

      it "counts CSRF events by reason" do
        %i[csrf_token_fallback csrf_request_blocked csrf_javascript_blocked].each do |name|
          assert_metric(
            record(name, controller: "ArticlesController", action: "create"),
            name:       "rails.action_controller.csrf_events",
            kind:       :counter,
            dimensions: {"rails.action_controller.csrf.reason" => name.to_s.delete_prefix("csrf_")}
          )
        end
      end

      it "times fragment cache operations by operation" do
        assert_metric(
          record(:exist_fragment?, key: "views/x"),
          name:       "rails.action_controller.fragment_cache.duration",
          kind:       :histogram,
          dimensions: {"rails.cache.operation.name" => "exist_fragment"}
        )
      end
    end

    class RequestTest < ActionDispatch::IntegrationTest
      it "records the controller metrics of a request" do
        metrics = semantic_logger_metrics { get article_url(:new) }

        assert_metric(
          metrics,
          name:       "rails.action_controller.process_action.duration",
          dimensions: {"code.function.name" => "ArticlesController#new", "http.response.status_code" => 200}
        )
      end

      it "counts a redirect by the action that made it" do
        metrics = semantic_logger_metrics { get redirector_articles_url }

        assert_metric(
          metrics,
          name:       "rails.action_controller.redirects",
          dimensions: {"http.response.status_code" => 302, "code.function.name" => "ArticlesController#redirector"}
        )
      end
    end
  end
end
