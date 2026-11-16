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
  # Active Support 8.0.0 to 8.0.5.2 pass `quirks_mode:` to JSON.generate, which json 3 removed, so
  # every #to_json raises "unknown keyword: quirks_mode" and the :json formatter writes nothing.
  # Remove once an 8.0 release includes rails/rails@2786de26c6 ("Stop passing `quirks_mode` to
  # JSON.parse").
  gem "json", "< 3"
end

appraise "rails_8.1" do
  gem "rails", "~> 8.1.1"
  gem "sidekiq", "~> 8.1"
end

appraise "rails_edge" do
  gem "rails", github: "rails/rails", branch: "main"
  gem "sidekiq", "~> 8.1"
end
