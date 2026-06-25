Dummy::Application.routes.draw do
  get "welcome/index"

  resources :articles do
    collection do
      get :redirector
      get :rescued
      get :filtered
      get :halted
      get :download_data
      get :download_file
      post :upload
    end
  end

  resource :dashboard, controller: :dashboard

  root "welcome#index"
end
