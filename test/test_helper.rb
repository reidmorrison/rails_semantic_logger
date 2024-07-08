ENV["RAILS_ENV"] ||= "test"
ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "1"
# Load first so Sidekiq thinks it is running as a server instance
require "sidekiq/cli"
if defined?(Sidekiq::DEFAULT_ERROR_HANDLER)
  # Set by Sidekiq CLI at startup
  Sidekiq.options[:error_handlers] << Sidekiq::DEFAULT_ERROR_HANDLER
end
require_relative "dummy/config/environment"

require "rails/test_help"
require "minitest/autorun"
require "minitest/rails"
require "amazing_print"

require_relative "payload_collector"

# Include the complete backtrace?
Minitest.backtrace_filter = Minitest::BacktraceFilter.new if ENV["BACKTRACE"].present?
Rails.backtrace_cleaner.remove_silencers!

# Add Semantic Logger helpers for Minitest
Minitest::Test.include SemanticLogger::Test::Minitest

ActionMailer::Base.delivery_method = :test
