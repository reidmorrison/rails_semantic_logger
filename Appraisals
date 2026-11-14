appraise "rails_7.2" do
  gem "rails", "~> 7.2.0"
  gem "sidekiq", "~> 7.2"
  # Rails 7.2.4 and Sidekiq 7.3.10 require connection_pool < 3. Without this pin Bundler picks
  # connection_pool 3 and falls back to the older Rails and Sidekiq releases that do not cap it.
  gem "connection_pool", "< 3"
end

appraise "rails_8.0" do
  gem "rails", "~> 8.0.0"
  gem "sidekiq", "~> 8.0.0"
end

appraise "rails_8.1" do
  gem "rails", "~> 8.1.1"
  gem "sidekiq", "~> 8.1"
end

appraise "rails_edge" do
  gem "rails", github: "rails/rails", branch: "main"
  gem "sidekiq", "~> 8.1"
end
