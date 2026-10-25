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

    # Rails 8.1+ instruments this event; earlier versions never do, so call the handler directly.
    describe "#open_redirect" do
      it "logs the location and request at :warn with the redirect's stack trace" do
        request = ActionDispatch::TestRequest.create("REQUEST_METHOD" => "POST", "PATH_INFO" => "/articles")
        event   = ActiveSupport::Notifications::Event.new(
          "open_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://elsewhere.example.com/", request: request, stack_trace: ["app/x.rb:1"]}
        )

        messages = semantic_logger_events do
          subscriber.open_redirect(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :warn,
          message: "Open redirect detected",
          payload: {location: "https://elsewhere.example.com/", request_method: "POST", request_path: "/articles"},
          metric:  "rails.controller.open_redirect"
        )
        assert_equal ["app/x.rb:1"], messages[0].backtrace
      end

      it "leaves request details out when the event has no request" do
        event = ActiveSupport::Notifications::Event.new(
          "open_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://elsewhere.example.com/", request: nil, stack_trace: nil}
        )

        messages = semantic_logger_events do
          subscriber.open_redirect(event)
        end

        assert_equal 1, messages.count, messages
        assert_equal({location: "https://elsewhere.example.com/"}, messages[0].payload)
      end

      it "logs under the logger of the controller handling the request" do
        request                     = ActionDispatch::TestRequest.create
        request.controller_instance = ArticlesController.new
        event                       = ActiveSupport::Notifications::Event.new(
          "open_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://elsewhere.example.com/", request: request, stack_trace: nil}
        )

        messages = semantic_logger_events do
          subscriber.open_redirect(event)
        end

        assert_equal 1, messages.count, messages
        assert_equal "ArticlesController", messages[0].name
      end

      it "removes gem frames from the backtrace" do
        gem_frame = "#{Gem.path.first}/gems/actionpack-8.1.4/lib/action_controller/metal/redirecting.rb:293"
        event     = ActiveSupport::Notifications::Event.new(
          "open_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://elsewhere.example.com/", request: nil, stack_trace: [gem_frame, "app/x.rb:1"]}
        )

        messages = semantic_logger_events do
          subscriber.open_redirect(event)
        end

        assert_equal ["app/x.rb:1"], messages[0].backtrace
      end

      it "does not fail when ActionController::Base has no logger" do
        event = ActiveSupport::Notifications::Event.new(
          "open_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {location: "https://elsewhere.example.com/", request: nil, stack_trace: nil}
        )

        ActionController::Base.stub(:logger, nil) do
          assert_nil subscriber.open_redirect(event)
        end
      end
    end

    # Rails 8.1+ instruments this event; earlier versions never do, so call the handler directly.
    describe "#unsafe_redirect" do
      it "logs the message and url at :warn with the redirect's stack trace" do
        event = ActiveSupport::Notifications::Event.new(
          "unsafe_redirect.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {url: "foo", message: 'Path relative URL redirect detected: "foo"', stack_trace: ["app/x.rb:1"]}
        )

        messages = semantic_logger_events do
          subscriber.unsafe_redirect(event)
        end

        assert_equal 1, messages.count, messages
        assert_semantic_logger_event(
          messages[0],
          level:   :warn,
          message: 'Path relative URL redirect detected: "foo"',
          payload: {url: "foo"},
          metric:  "rails.controller.unsafe_redirect"
        )
        assert_equal ["app/x.rb:1"], messages[0].backtrace
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

    # Rails 8.2+ instruments these events; earlier versions never do, so call the handlers directly.
    describe "CSRF events" do
      def csrf_event(name, sec_fetch_site: "cross-site", message: nil)
        ActiveSupport::Notifications::Event.new(
          "#{name}.action_controller",
          5.seconds.ago,
          Time.zone.now,
          SecureRandom.uuid,
          {
            request:        nil,
            controller:     "ArticlesController",
            action:         "create",
            sec_fetch_site: sec_fetch_site,
            message:        message
          }
        )
      end

      describe "#csrf_request_blocked" do
        it "logs Rails' message at :warn" do
          event = csrf_event(:csrf_request_blocked, message: "Can't verify CSRF token authenticity.")

          messages = semantic_logger_events do
            subscriber.csrf_request_blocked(event)
          end

          assert_equal 1, messages.count, messages
          assert_semantic_logger_event(
            messages[0],
            level:   :warn,
            name:    "ArticlesController",
            message: "Can't verify CSRF token authenticity.",
            payload: {controller: "ArticlesController", action: "create", sec_fetch_site: "cross-site"},
            metric:  "rails.controller.csrf_request_blocked"
          )
        end
      end

      describe "#csrf_javascript_blocked" do
        it "logs Rails' message at :warn" do
          event = csrf_event(:csrf_javascript_blocked, message: "Security warning: an embedded <script> tag")

          messages = semantic_logger_events do
            subscriber.csrf_javascript_blocked(event)
          end

          assert_equal 1, messages.count, messages
          assert_semantic_logger_event(
            messages[0],
            level:   :warn,
            name:    "ArticlesController",
            message: "Security warning: an embedded <script> tag",
            payload: {controller: "ArticlesController", action: "create", sec_fetch_site: "cross-site"},
            metric:  "rails.controller.csrf_javascript_blocked"
          )
        end
      end

      describe "#csrf_token_fallback" do
        it "logs at :warn and leaves a missing Sec-Fetch-Site out of the payload" do
          event = csrf_event(:csrf_token_fallback, sec_fetch_site: nil)

          messages = semantic_logger_events do
            subscriber.csrf_token_fallback(event)
          end

          assert_equal 1, messages.count, messages
          assert_semantic_logger_event(
            messages[0],
            level:   :warn,
            name:    "ArticlesController",
            message: "Falling back to CSRF token verification",
            payload: {controller: "ArticlesController", action: "create"},
            metric:  "rails.controller.csrf_token_fallback"
          )
        end
      end

      it "logs nothing when log_warning_on_csrf_failure is off" do
        original = ActionController::Base.log_warning_on_csrf_failure
        ActionController::Base.log_warning_on_csrf_failure = false

        messages = semantic_logger_events do
          subscriber.csrf_request_blocked(csrf_event(:csrf_request_blocked, message: "blocked"))
          subscriber.csrf_javascript_blocked(csrf_event(:csrf_javascript_blocked, message: "blocked"))
          subscriber.csrf_token_fallback(csrf_event(:csrf_token_fallback))
        end

        assert_empty messages
      ensure
        ActionController::Base.log_warning_on_csrf_failure = original
      end
    end
  end
end
