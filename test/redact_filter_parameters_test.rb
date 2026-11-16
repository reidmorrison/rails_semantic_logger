require_relative "test_helper"

class RedactFilterParametersTest < Minitest::Test
  # Keeps the payloads of this test's entries, as the appenders receive them.
  class PayloadAppender < SemanticLogger::Subscriber
    def payloads
      @payloads ||= []
    end

    def log(log)
      payloads << log.payload if log.name == "RedactFilterParametersTest"
    end
  end

  describe "redacting the application's filter parameters" do
    # Returns the payload of an entry logged with the supplied payload, as an appender receives it.
    def logged_payload(payload)
      appender = SemanticLogger.add_appender(appender: PayloadAppender.new)
      SemanticLogger["RedactFilterParametersTest"].info("Redact", payload)
      SemanticLogger.flush
      appender.payloads.last
    ensure
      SemanticLogger.remove_appender(appender) if appender
    end

    describe "once the application has initialized" do
      it "is on by default" do
        assert RailsSemanticLogger::Options.new.redact_filter_parameters
        assert Rails.application.config.rails_semantic_logger.redact_filter_parameters
      end

      it "makes the application's filter parameters the sensitive keys" do
        assert_kind_of ActiveSupport::ParameterFilter, SemanticLogger.sensitive_keys
      end

      it "redacts them in every appender" do
        # The dummy application filters :password.
        assert_equal(
          {password: "[FILTERED]", name: "Jack"},
          logged_payload(password: "secret", name: "Jack")
        )
      end
    end

    describe ".redact_filter_parameters" do
      before do
        @sensitive_keys               = SemanticLogger.sensitive_keys
        SemanticLogger.sensitive_keys = nil
      end

      after do
        SemanticLogger.sensitive_keys = @sensitive_keys
      end

      # Returns an application configuration with the supplied filter parameters.
      def config(filter_parameters, redact: true)
        options                          = RailsSemanticLogger::Options.new
        options.redact_filter_parameters = redact
        Struct.new(:rails_semantic_logger, :filter_parameters).new(options, filter_parameters)
      end

      it "redacts Symbol, String, and Regexp filters" do
        RailsSemanticLogger.redact_filter_parameters(config([:passw, "ssn", /\Aapi_/]))

        assert_equal(
          {password: "[FILTERED]", ssn: "[FILTERED]", api_id: "[FILTERED]", name: "Jack"},
          logged_payload(password: "secret", ssn: "123", api_id: 1, name: "Jack")
        )
      end

      it "does nothing when turned off" do
        RailsSemanticLogger.redact_filter_parameters(config([:password], redact: false))

        assert_nil SemanticLogger.sensitive_keys
        assert_equal({password: "secret"}, logged_payload(password: "secret"))
      end

      it "keeps the sensitive keys that the application assigned" do
        SemanticLogger.sensitive_keys = [:pin]
        RailsSemanticLogger.redact_filter_parameters(config([:password]))

        assert_equal [:pin], SemanticLogger.sensitive_keys
        assert_equal(
          {password: "secret", pin: "[FILTERED]"},
          logged_payload(password: "secret", pin: 1234)
        )
      end

      # A Proc filter changes the value it is given, which is nil when Semantic Logger asks about
      # a key, so this one would raise and the whole payload would be replaced.
      it "leaves out Proc filters" do
        reverse_secret = ->(key, value) { value.reverse! if key.to_s.include?("secret") }
        RailsSemanticLogger.redact_filter_parameters(config([:password, reverse_secret]))

        assert_equal(
          {password: "[FILTERED]", secret: "abc"},
          logged_payload(password: "x", secret: "abc")
        )
      end

      it "leaves the sensitive keys unset when there are only Proc filters" do
        RailsSemanticLogger.redact_filter_parameters(config([->(_key, _value) {}]))

        assert_nil SemanticLogger.sensitive_keys
      end
    end
  end
end
