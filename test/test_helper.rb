ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

# Needed for Dummy test app
require "minitest/autorun"
require "awesome_print"

require "rails/test_help"
require_relative "mock_logger"

# Include the complete backtrace?
Minitest.backtrace_filter = Minitest::BacktraceFilter.new if ENV["BACKTRACE"].present?
Rails.backtrace_cleaner.remove_silencers!
