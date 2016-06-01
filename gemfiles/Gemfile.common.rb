source 'https://rubygems.org'

gem 'rake', '~> 10.0'
gem 'minitest'
gem 'minitest-reporters'
gem 'minitest-stub_any_instance'
gem 'awesome_print'

gem 'sqlite3', platform: :ruby
gem 'jdbc-sqlite3', platform: :jruby
gem 'activerecord-jdbcsqlite3-adapter', platform: :jruby
# active_model_serializers v0.10 requires Ruby v2
gem 'active_model_serializers', '~> 0.9.5'
