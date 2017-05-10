Dummy::Application.routes.draw do
  get 'welcome/index'

  resources :articles

  root 'welcome#index'
end
