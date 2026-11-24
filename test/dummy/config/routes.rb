# A mountable engine, to check the route recorded for its requests.
module Blog
  class Engine < ::Rails::Engine
    isolate_namespace Blog
  end
end

Blog::Engine.routes.draw do
  get "posts/:id", to: ->(_env) { [200, {"content-type" => "text/plain"}, ["post"]] }
end

Dummy::Application.routes.draw do
  get "welcome/index"

  resources :articles do
    collection do
      get :redirector
      get :open_redirector
      get :path_relative_redirector
      get :rescued
      get :filtered
      get :halted
      get :download_data
      get :download_file
      post :upload
    end
  end

  resource :dashboard, controller: :dashboard

  # A Rack application mounted at a path, an engine, and both under a dynamic segment.
  mount ->(_env) { [200, {"content-type" => "text/plain"}, ["mounted"]] }, at: "/mounted"
  mount Blog::Engine, at: "/blog"
  scope ":locale" do
    mount ->(_env) { [200, {"content-type" => "text/plain"}, ["localized"]] }, at: "/localized"
    mount Blog::Engine, at: "/news", as: "localized_blog"
  end

  # Matches the path, then passes the request on: no route serves it.
  get "cascading/:id", to: "articles#show", constraints: ->(_request) { false }

  root "welcome#index"
end
