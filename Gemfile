source "https://rubygems.org"

gemspec

# Semantic Logger 5.3 is not released yet, and the changes built on this need it. Once it is, remove
# this line and run `appraisal generate`, since CI installs from the gemfiles/ that it generates.
gem "semantic_logger", github: "reidmorrison/semantic_logger", branch: "main"

gem "appraisal"
gem "puma"

gem "active_model_serializers"
gem "amazing_print"
gem "minitest"
gem "minitest-rails"
gem "rake"
gem "simplecov", require: false
gem "solargraph", require: false, platform: :ruby

gem "rails", "~> 8.1.0"
gem "sidekiq"
gem "solid_queue", "~> 1.4"
gem "sqlite3"

gem "rubocop"
gem "rubocop-minitest"
gem "rubocop-rake"
