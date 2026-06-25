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

  private

  def tagged_logger_proxy
    proxy = ActionCable::Connection::TaggedLoggerProxy.allocate
    proxy.singleton_class.define_method(:tags) { %i[request_id user_id] }
    proxy
  end
end
