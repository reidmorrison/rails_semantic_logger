require_relative "../test_helper"

class DashboardControllerTest < ActionController::TestCase
  describe DashboardController do
    before do
      # Use a mock logger that just keeps the last logged entry in an instance variable
      SemanticLogger.default_level   = :trace
      SemanticLogger.backtrace_level = nil
      @mock_logger                   = MockLogger.new
      @appender                      = SemanticLogger.add_appender(logger: @mock_logger, formatter: :raw)
      @logger                        = SemanticLogger['Test']

      assert_equal [], SemanticLogger.tags
      assert_equal 65535, SemanticLogger.backtrace_level_index
    end

    after do
      SemanticLogger.remove_appender(@appender)
    end

    describe 'GET #show' do
      before do
        get :show
      end

      it 'has no errors' do
        assert_response :success
      end

      it 'successfully logs message' do
        SemanticLogger.flush
        actual = @mock_logger.message

        assert_equal 'Completed #show', actual[:message]

        assert payload = actual[:payload], actual
        assert_equal 'show', payload[:action], payload
        assert_equal 'DashboardController', payload[:controller], payload
        assert_equal 'HTML', payload[:format], payload
        assert_equal 'GET', payload[:method], payload

        assert_equal '/dashboard', payload[:path], payload
        assert_equal 200, payload[:status], payload
        assert_equal 'OK', payload[:status_message], payload
      end

    end
  end
end
