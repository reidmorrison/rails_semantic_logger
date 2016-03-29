require_relative 'test_helper'

class RailsTest < ActiveSupport::TestCase
  test 'truth' do
    assert_kind_of SemanticLogger::Logger, Rails.logger
  end
end
