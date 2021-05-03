ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

# Needed for Dummy test app
require "minitest/autorun"
require "amazing_print"

require "rails/test_help"
require_relative "mock_logger"
require_relative "payload_collector"

# Include the complete backtrace?
Minitest.backtrace_filter = Minitest::BacktraceFilter.new if ENV["BACKTRACE"].present?
Rails.backtrace_cleaner.remove_silencers!
