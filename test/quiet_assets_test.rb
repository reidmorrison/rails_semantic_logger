require_relative "test_helper"

class QuietAssetsTest < Minitest::Test
  describe "quiet_assets" do
    it "derives config.rails_semantic_logger.quiet_assets from config.assets.quiet" do
      assert Rails.application.config.rails_semantic_logger.quiet_assets
    end

    it "clears config.assets.quiet so Sprockets can find the Rack::Logger middleware" do
      refute Rails.application.config.assets.quiet
    end

    it "installs a filter on the Rack logger that silences asset requests" do
      filter = RailsSemanticLogger::Rack::Logger.logger.filter

      refute_nil filter

      log         = SemanticLogger::Log.new("Rack", :info)
      log.payload = {path: "/assets/application-abc123.js"}

      refute filter.call(log)
    end

    it "does not silence non-asset requests" do
      filter = RailsSemanticLogger::Rack::Logger.logger.filter

      log         = SemanticLogger::Log.new("Rack", :info)
      log.payload = {path: "/welcome/index"}

      assert filter.call(log)
    end
  end
end
