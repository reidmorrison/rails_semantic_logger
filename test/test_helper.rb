# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb', __FILE__)
require 'rails/test_help'

Rails.backtrace_cleaner.remove_silencers!

require 'minitest/rails'
require 'minitest/reporters'

# See every test and how long it took
MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new
