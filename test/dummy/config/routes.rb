Dummy::Application.routes.draw do
  get "welcome/index"

  resources :articles do
    collection do
      get :redirector
      get :rescued
      get :filtered
    end
  end

  resource :dashboard, controller: :dashboard

  root "welcome#index"
end
