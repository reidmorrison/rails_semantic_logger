require_relative '../test_helper'

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Use a mock logger that just keeps the last logged entry in an instance variable
    SemanticLogger.default_level   = :trace
    SemanticLogger.backtrace_level = nil
    @mock_logger                   = MockLogger.new
    @appender                      = SemanticLogger.add_appender(logger: @mock_logger, formatter: :raw)
    @logger                        = SemanticLogger['Test']
    @hash                          = {session_id: 'HSSKLEU@JDK767', tracking_number: 12_345}

    assert_equal [], SemanticLogger.tags
    assert_equal 65_535, SemanticLogger.backtrace_level_index
  end

  teardown do
    SemanticLogger.remove_appender(@appender)
  end

  test 'GET #new shows new article' do
    get article_url(:new)
    assert_response :success
  end

  def params
    {
      article: {
        text:  'Text1',
        title: 'Title1'
      }
    }
  end

  test 'POST #create has no errors' do
    params = {params: self.params} if Rails.version.to_i >= 5
    post articles_url(params)

    assert_response :success
  end

  test 'POST #create successfully logs message' do
    params = {params: self.params} if Rails.version.to_i >= 5
    post articles_url(params)

    SemanticLogger.flush
    actual = @mock_logger.message

    assert_equal 'Completed #create', actual[:message]
    assert_equal 'ArticlesController', actual[:name]

    assert payload = actual[:payload], actual
    assert_equal 'create', payload[:action], payload
    assert_equal 'ArticlesController', payload[:controller], payload
    assert_equal 'HTML', payload[:format], payload
    assert_equal 'POST', payload[:method], payload
    # Only Rails 5 passes the arguments through
    if Rails.version.to_i >= 5
      assert_equal({'article' => {'text' => 'Text1', 'title' => 'Title1'}}, payload[:params], payload)
    end
    assert_equal '/articles', payload[:path], payload
    assert_equal 200, payload[:status], payload
    assert_equal 'OK', payload[:status_message], payload
    assert (payload[:view_runtime] >= 0.0), payload
    assert((payload[:db_runtime] >= 0.0), payload) unless defined?(JRuby)
  end
end
