require_relative 'test_helper'

class ActiveRecordTest < Minitest::Test
  describe 'ActiveRecord' do
    before do
      # Use a mock logger that just keeps the last logged entry in an instance variable
      SemanticLogger.default_level   = :trace
      SemanticLogger.backtrace_level = nil
      @mock_logger                   = MockLogger.new
      @appender                      = SemanticLogger.add_appender(logger: @mock_logger, formatter: :raw)
      @logger                        = SemanticLogger['Test']
      @hash                          = {session_id: 'HSSKLEU@JDK767', tracking_number: 12345}

      assert_equal [], SemanticLogger.tags
      assert_equal 65535, SemanticLogger.backtrace_level_index
    end

    after do
      SemanticLogger.remove_appender(@appender)
    end

    describe 'logs' do
      it 'sql' do
        Sample.first

        SemanticLogger.flush
        actual = @mock_logger.message
        ap actual
        assert actual[:message].include?('Sample'), actual[:message]
        assert actual[:payload], actual
        assert actual[:payload][:sql], actual[:payload]
      end
    end

  end
end
