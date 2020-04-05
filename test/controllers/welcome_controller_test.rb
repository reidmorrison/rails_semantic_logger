require_relative "../test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "Welcome Controller should get index" do
    get "/welcome/index"
    assert_response :success
  end
end
