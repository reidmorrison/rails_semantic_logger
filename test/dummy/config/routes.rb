Dummy::Application.routes.draw do
  get "welcome/index"

  resources :articles

  resource :dashboard, controller: :dashboard

  root "welcome#index"
end
