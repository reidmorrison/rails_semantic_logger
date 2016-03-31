$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb', __FILE__)

Rails.backtrace_cleaner.remove_silencers!

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'awesome_print'
require 'rails_semantic_logger'

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new
