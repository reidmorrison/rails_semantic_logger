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
    end
  end
end
