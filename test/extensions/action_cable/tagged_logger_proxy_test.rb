require_relative "../../test_helper"

class TaggedLoggerProxyTest < Minitest::Test
  class LoggerWithoutTags
    attr_reader :received_tags

    def tagged(*tags)
      @received_tags = tags
      yield
    end
  end

  class LoggerWithTags < LoggerWithoutTags
    attr_reader :tags

    def initialize(tags)
      super()
      @tags = tags
    end
  end

  def test_tag_does_not_require_logger_tags
    logger = LoggerWithoutTags.new

    tagged_logger_proxy.send(:tag, logger) { :ok }

    assert_equal %i[request_id user_id], logger.received_tags
  end

  def test_tag_removes_duplicate_tags_when_logger_exposes_tags
    logger = LoggerWithTags.new([:request_id])

    tagged_logger_proxy.send(:tag, logger) { :ok }

    assert_equal [:user_id], logger.received_tags
  end

  def test_tag_yields_when_logger_does_not_support_tagging
    logger = Object.new

    result = tagged_logger_proxy.send(:tag, logger) { :ok }

    assert_equal :ok, result
  end

  # Records the full Semantic Logger severity signature so we can assert the
  # proxy forwards payload/exception instead of dropping them (see #220).
  class RecordingLogger
    attr_reader :calls

    def initialize
      @calls = []
    end

    def tags
      []
    end

    def tagged(*)
      yield
    end

    %i[debug info warn error fatal unknown].each do |severity|
      define_method(severity) do |message = nil, payload = nil, exception = nil, &block|
        @calls << [severity, message, payload, exception]
        block&.call
      end
    end
  end

  def test_info_forwards_payload_to_wrapped_logger
    logger = RecordingLogger.new

    tagged_logger_proxy(logger).info("Started request", user_id: 7)

    assert_equal [[:info, "Started request", {user_id: 7}, nil]], logger.calls
  end

  def test_error_forwards_exception_to_wrapped_logger
    logger    = RecordingLogger.new
    exception = StandardError.new("boom")

    tagged_logger_proxy(logger).error("WebSocket error", nil, exception)

    assert_equal [[:error, "WebSocket error", nil, exception]], logger.calls
  end

  def test_message_only_severity_still_works
    logger = RecordingLogger.new

    tagged_logger_proxy(logger).warn("Late message")

    assert_equal [[:warn, "Late message", nil, nil]], logger.calls
  end

  # A standard Ruby Logger (e.g. wrapped by ActionCable::Connection::TestCase) only
  # accepts a single `progname` argument and raises ArgumentError given more. See #317.
  def test_plain_ruby_logger_does_not_raise
    io     = StringIO.new
    logger = Logger.new(io)

    tagged_logger_proxy(logger).error("An unauthorized connection attempt was rejected")

    assert_match(/An unauthorized connection attempt was rejected/, io.string)
  end

  private

  def tagged_logger_proxy(logger = nil)
    proxy = ActionCable::Connection::TaggedLoggerProxy.allocate
    proxy.singleton_class.define_method(:tags) { %i[request_id user_id] }
    proxy.instance_variable_set(:@logger, logger) if logger
    proxy
  end
end
