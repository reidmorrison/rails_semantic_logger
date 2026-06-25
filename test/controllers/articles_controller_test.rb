require_relative "../test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  describe ArticlesController do
    let(:params) { {article: {text: "Text1", title: "Title1"}} }

    describe "#new" do
      it "shows new article" do
        get article_url(:new)

        assert_response :success
      end
    end

    describe "#create" do
      it "has no errors" do
        post articles_url(params: params)

        assert_response :success
      end

      it "successfully logs message" do
        messages = semantic_logger_events do
          post articles_url(params: params)
        end
        assert_equal 5, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          message: "Started",
          name:    "Rack",
          level:   :debug,
          payload: {
            method: "POST",
            path:   "/articles?article%5Btext%5D=Text1&article%5Btitle%5D=Title1",
            ip:     "127.0.0.1"
          }
        )

        assert_semantic_logger_event(
          messages[1],
          message: "Processing #create",
          name:    "ArticlesController",
          level:   :debug
        )

        assert_semantic_logger_event(
          messages[2],
          message: "Rendering",
          name:    "ActionView",
          level:   :debug,
          payload: {
            template: "text template"
          }
        )

        assert_semantic_logger_event(
          messages[3],
          message: "Rendered",
          name:    "ActionView",
          level:   :debug
        )

        assert_semantic_logger_event(
          messages[4],
          message:          "Completed #create",
          name:             "ArticlesController",
          level:            :info,
          payload_includes: {
            controller:     "ArticlesController",
            action:         "create",
            params:         {
              "article" => {
                "text"  => "Text1",
                "title" => "Title1"
              }
            },
            format:         "HTML",
            method:         "POST",
            path:           "/articles",
            status:         200,
            status_message: "OK"
          }
        )
      end

      it "customize action message" do
        old_action_message_format = RailsSemanticLogger::ActionController::LogSubscriber.action_message_format
        RailsSemanticLogger::ActionController::LogSubscriber.action_message_format = -> (message, payload) do
          "#{message} #{payload[:controller]}##{payload[:action]}"
        end

        messages = semantic_logger_events do
          post articles_url(params: params)
        end
        assert_equal 5, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          message: "Started"
        )

        assert_semantic_logger_event(
          messages[1],
          message: "Processing ArticlesController#create"
        )

        assert_semantic_logger_event(
          messages[2],
          message: "Rendering"
        )

        assert_semantic_logger_event(
          messages[3],
          message: "Rendered"
        )

        assert_semantic_logger_event(
          messages[4],
          message: "Completed ArticlesController#create",
        )
      ensure
        RailsSemanticLogger::ActionController::LogSubscriber.action_message_format = old_action_message_format
      end
    end

    describe "structured payload" do
      it "includes gc_time and allocations on completed" do
        messages = semantic_logger_events do
          post articles_url(params: params)
        end

        completed = messages.find { |m| m.message&.start_with?("Completed") }
        assert completed, messages
        assert completed.payload.key?(:allocations), completed.payload
        assert completed.payload.key?(:gc_time), completed.payload
      end
    end

    describe "#redirector" do
      it "logs the redirect location" do
        messages = semantic_logger_events do
          get redirector_articles_url
        end

        redirect = messages.find { |m| m.message == "Redirected to" }
        assert redirect, messages
        assert_equal article_url(:new), redirect.payload[:location]
      end

      it "logs the redirect source when verbose_redirect_logs is enabled" do
        skip "verbose_redirect_logs added in Rails 8.1" unless ActionDispatch.respond_to?(:verbose_redirect_logs)

        old = ActionDispatch.verbose_redirect_logs
        begin
          ActionDispatch.verbose_redirect_logs = true
          messages = semantic_logger_events do
            get redirector_articles_url
          end

          redirect = messages.find { |m| m.message == "Redirected to" }
          assert redirect, messages
          assert redirect.payload.key?(:source), redirect.payload
        ensure
          ActionDispatch.verbose_redirect_logs = old
        end
      end
    end

    describe "#rescued" do
      it "logs the rescue_from handler" do
        skip "rescue_from_callback instrumented in Rails 8.1" if Rails.version.to_f < 8.1

        messages = semantic_logger_events do
          get rescued_articles_url
        end

        rescued = messages.find { |m| m.message&.start_with?("rescue_from handled") }
        assert rescued, messages
        assert_equal "ArticlesController::Handled", rescued.payload[:exception]
        assert_equal "boom", rescued.payload[:exception_message]
      end
    end

    describe "#filtered" do
      it "logs unpermitted parameters with keys and context" do
        old = ActionController::Parameters.action_on_unpermitted_parameters
        begin
          ActionController::Parameters.action_on_unpermitted_parameters = :log
          messages = semantic_logger_events do
            get filtered_articles_url(title: "ok", bogus: "nope")
          end

          unpermitted = messages.find { |m| m.message&.start_with?("Unpermitted parameter") }
          assert unpermitted, messages
          assert_equal :debug, unpermitted.level
          assert_includes unpermitted.payload[:keys], "bogus"
          assert unpermitted.payload.key?(:context), unpermitted.payload
        ensure
          ActionController::Parameters.action_on_unpermitted_parameters = old
        end
      end
    end

    describe "#show" do
      it "raises and logs exception" do
        # we're testing ActionDispatch::DebugExceptions in fact
        messages = semantic_logger_events do
          old_show = Rails.application.env_config["action_dispatch.show_exceptions"]
          begin
            Rails.application.env_config["action_dispatch.show_exceptions"] = :all
            get article_url(:show)
          rescue ActiveRecord::RecordNotFound => e
            # expected
          ensure
            Rails.application.env_config["action_dispatch.show_exceptions"] = old_show
          end
        end
        assert_equal 4, messages.count, messages
        assert_kind_of ActiveRecord::RecordNotFound, messages[3].exception
      end

      it "raises and does not log exception when action_dispatch.log_rescued_responses is false" do
        skip "Not applicable to older rails" if Rails.version.to_f < 7.1
        # we're testing ActionDispatch::DebugExceptions here too
        messages = semantic_logger_events do
          old_show = Rails.application.env_config["action_dispatch.show_exceptions"]
          old_log_rescued_responses = Rails.application.env_config["action_dispatch.log_rescued_responses"]

          begin
            Rails.application.env_config["action_dispatch.show_exceptions"] = :all
            Rails.application.env_config["action_dispatch.log_rescued_responses"] = false
            get article_url(:show)
          rescue ActiveRecord::RecordNotFound => e
            # expected
          ensure
            Rails.application.env_config["action_dispatch.show_exceptions"] = old_show
            Rails.application.env_config["action_dispatch.log_rescued_responses"] = old_log_rescued_responses
          end
        end
        assert_equal 3, messages.count, messages
      end
    end
  end
end
