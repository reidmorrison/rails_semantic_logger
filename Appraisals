appraise "rails_5.1" do
  gem "rails", "~> 5.1.5"
  gem "sqlite3", "~> 1.3.0", platform: :ruby
  gem "activerecord-jdbcsqlite3-adapter", "~> 51.0", platform: :jruby
end

appraise "rails_5.2" do
  gem "rails", "~> 5.2.0"
  gem "sqlite3", "~> 1.3.0", platform: :ruby
  gem "activerecord-jdbcsqlite3-adapter", "~> 52.0", platform: :jruby
end

appraise "rails_6.0" do
  gem "rails", "~> 6.0.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 60.0", platform: :jruby
  gem "sqlite3", "~> 1.4.0", platform: :ruby
end

appraise "rails_6.1" do
  gem "rails", "~> 6.1.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 61.0", platform: :jruby
  gem "sqlite3", "~> 1.4.0", platform: :ruby
end

appraise "rails_7.0" do
  # Remove this deprecated gem once the following patch is released
  # https://github.com/rails-api/active_model_serializers/pull/2428
  gem "thread_safe", "~> 0.3.6"

  gem "rails", "~> 7.0.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 70.0", platform: :jruby
  gem "sqlite3", "~> 1.4.0", platform: :ruby
end
