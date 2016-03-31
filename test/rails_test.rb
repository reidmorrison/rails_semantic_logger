require_relative 'test_helper'

class RailsTest < Minitest::Test
  describe 'Rails' do
    describe '.logger' do
      it 'replaces the Rails logger' do
        assert_kind_of SemanticLogger::Logger, Rails.logger
        assert_kind_of SemanticLogger::Formatters::Color, Rails.logger.formatter
      end

      it 'uses the colorized formatter' do
        assert_kind_of SemanticLogger::Formatters::Color, Rails.logger.formatter
      end
    end
  end
end
