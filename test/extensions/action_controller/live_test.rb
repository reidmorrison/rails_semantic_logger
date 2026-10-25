require_relative "../../test_helper"

class LiveTest < Minitest::Test
  class StreamingController < ActionController::Base
    include ActionController::Live
  end

  # The patch is deferred until Action Controller loads, so check it still lands.
  def test_patch_is_applied_once_action_controller_has_loaded
    file, = ActionController::Live.instance_method(:log_error).source_location

    assert_match(%r{lib/rails_semantic_logger/extensions/action_controller/live\.rb\z}, file)
  end

  def test_log_error_logs_the_exception_itself
    exception = RuntimeError.new("boom")

    messages = semantic_logger_events do
      StreamingController.new.send(:log_error, exception)
    end

    assert_equal 1, messages.count, messages
    assert_semantic_logger_event(
      messages[0],
      level:     :fatal,
      name:      "LiveTest::StreamingController",
      exception: exception
    )
  end
end
