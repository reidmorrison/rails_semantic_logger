require_relative 'test_helper'

class RailsTest < Minitest::Test
  describe 'Rails' do
    describe '.logger' do
      it 'sets the Rails logger' do
        assert_kind_of SemanticLogger::Logger, Rails.logger
      end
    end
  end
end
