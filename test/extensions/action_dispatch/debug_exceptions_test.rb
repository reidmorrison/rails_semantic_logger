require_relative "../../test_helper"

module ActionDispatch
  class DebugExceptionsTest < Minitest::Test
    # Rails' own backtrace cleaner, as an application has: test_helper removes the silencers from
    # Rails.backtrace_cleaner. Rails counts this file, under test/, as application code, so this
    # cleaner also silences it. An exception raised here, or by a request made from here, then has
    # only framework frames, as one raised in middleware for a request from the app server has.
    def self.rails_cleaner
      Rails::BacktraceCleaner.new.tap { |cleaner| cleaner.add_silencer { |line| line.include?(File.basename(__FILE__)) } }
    end

    describe "ActionDispatch::DebugExceptions" do
      let(:rails_cleaner) { DebugExceptionsTest.rails_cleaner }
      # Keeps only the frames of this file, as application frames.
      let(:app_cleaner) do
        ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
          cleaner.remove_silencers!
          cleaner.add_silencer { |line| !line.include?(File.basename(__FILE__)) }
        end
      end

      let(:routing_error) { raised(ActionController::RoutingError, 'No route matches [GET] "/missing"') }

      def raised(klass, message)
        raise klass, message
      rescue klass => e
        e
      end

      # Returns the entries logged by DebugExceptions for the exception, once it has rescued it.
      def log_error_events(exception, cleaner: rails_cleaner, env: {})
        env     = Rack::MockRequest.env_for("/missing", Rails.application.env_config.merge(env))
        wrapper = ActionDispatch::ExceptionWrapper.new(cleaner, exception)
        semantic_logger_events do
          ActionDispatch::DebugExceptions.new(->(_env) {}).send(:log_error, ActionDispatch::Request.new(env), wrapper)
        end
      end

      def log_error(exception, **)
        messages = log_error_events(exception, **)

        assert_equal 1, messages.count, messages
        messages.first
      end

      describe "an exception that Rails logs without a backtrace" do
        it "logs its class and message after the response's status, without the exception" do
          log = log_error(routing_error)

          assert_nil log.exception
          assert_equal '404 Not Found -- Exception: ActionController::RoutingError: No route matches [GET] "/missing"',
                       log.message
        end

        # Rails raises it while rescuing the Mime::Type::InvalidMimeType that caused it.
        it "logs another silent exception with its own status, and its cause" do
          exception =
            begin
              ActionDispatch::Request.new(Rack::MockRequest.env_for("/", "HTTP_ACCEPT" => "foo/bar/baz")).formats

              flunk "Rails accepted the Accept header"
            rescue ActionDispatch::Http::MimeNegotiation::InvalidType => e
              e
            end
          log = log_error(exception)

          assert_nil log.exception
          assert_match(/\A406 Not Acceptable -- Exception: ActionDispatch::Http::MimeNegotiation::InvalidType: /,
                       log.message)
          # Its cause has the same message, so only its class is added.
          assert_match(/ -- Cause: Mime::Type::InvalidMimeType\z/, log.message)
        end

        it "leaves the exception unchanged" do
          backtrace = routing_error.backtrace.dup
          log_error(routing_error)

          assert_equal backtrace, routing_error.backtrace
        end

        it "writes one line" do
          log    = log_error(routing_error)
          output = SemanticLogger::Formatters::Default.new.call(log, nil)

          assert_equal 1, output.lines.count, output
          assert_includes output, 'Exception: ActionController::RoutingError: No route matches [GET] "/missing"'
        end

        it "logs at the debug exception log level" do
          log = log_error(routing_error, env: {"action_dispatch.debug_exception_log_level" => ::Logger::WARN})

          assert_equal :warn, log.level
        end
      end

      describe "an exception that Rails logs with a backtrace" do
        it "logs a routing error raised from application code" do
          log = log_error(routing_error, cleaner: app_cleaner)

          assert_same routing_error, log.exception
        end

        it "logs another exception with no application frames, for which Rails logs the framework frames" do
          exception = raised(RuntimeError, "Failed")
          log       = log_error(exception)

          assert_same exception, log.exception
        end

        it "logs a routing error when BACKTRACE is set" do
          backtrace        = ENV.fetch("BACKTRACE", nil)
          ENV["BACKTRACE"] = "1"
          log              = log_error(routing_error)

          assert_same routing_error, log.exception
        ensure
          ENV["BACKTRACE"] = backtrace
        end
      end

      it "logs an exception whose backtrace was set from Strings, which Rails cannot read" do
        exception = ActionController::RoutingError.new("No route")
        exception.set_backtrace(["/gems/actionpack/lib/action_dispatch/middleware/debug_exceptions.rb:35:in 'call'"])
        log = log_error(exception)

        assert_same exception, log.exception
      end

      it "logs an exception that was never raised" do
        exception = ActionController::RoutingError.new("No route")
        log       = log_error(exception)

        assert_same exception, log.exception
      end

      it "logs the SyntaxError itself, not Rails' proxy for it" do
        exception = raised(SyntaxError, "syntax error, unexpected end-of-input")
        log       = log_error(exception, cleaner: app_cleaner)

        assert_same exception, log.exception
      end

      it "does not log a rescued response when log_rescued_responses is false" do
        messages = log_error_events(routing_error, env: {"action_dispatch.log_rescued_responses" => false})

        assert_empty messages
      end
    end
  end

  class DebugExceptionsIntegrationTest < ActionDispatch::IntegrationTest
    describe "ActionDispatch::DebugExceptions" do
      it "logs a request for a missing route on one line" do
        env_config = Rails.application.env_config
        settings   = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.backtrace_cleaner")
        env_config["action_dispatch.show_exceptions"]   = :all
        env_config["action_dispatch.backtrace_cleaner"] = DebugExceptionsTest.rails_cleaner

        messages = semantic_logger_events { get "/apple-touch-icon-120x120.png" }
        log      = messages.find { |entry| entry.message&.include?("RoutingError") }
        output   = SemanticLogger::Formatters::Default.new.call(log, nil)

        assert_includes output, "ActionController::Base -- 404 Not Found -- " \
                                "Exception: ActionController::RoutingError: No route matches"
        assert_equal 1, output.lines.count, output
      ensure
        env_config.merge!(settings)
      end
    end
  end
end
