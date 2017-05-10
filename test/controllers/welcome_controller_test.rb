require_relative '../test_helper'

class WelcomeControllerTest < ActionController::TestCase
  describe WelcomeController do
    before do
      get :index
    end

    it 'should get index' do
      assert_response :success
    end
  end
end
