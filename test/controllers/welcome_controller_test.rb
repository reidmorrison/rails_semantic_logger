require_relative "../test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  describe WelcomeController do
    describe "#index" do
      it "succeeds" do
        get "/welcome/index"

        assert_response :success
      end
    end
  end
end
