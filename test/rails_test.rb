require_relative "test_helper"

class RailsTest < Minitest::Test
  describe "Rails" do
    describe ".logger" do
      it "replaces the Rails logger" do
        assert_kind_of SemanticLogger::Logger, Rails.logger
      end

      it "uses the colorized formatter" do
        assert_kind_of SemanticLogger::Formatters::Color, SemanticLogger.appenders.first.formatter
      end

      it "is compatible with Rails logger" do
        assert_nil Rails.logger.formatter
        Rails.logger.formatter = "blah"
        assert_equal "blah", Rails.logger.formatter
      end
    end
  end
end
