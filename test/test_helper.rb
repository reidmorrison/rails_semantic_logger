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

# ActiveRecord filters bind values using ActiveRecord::Base.inspection_filter, which is built from
# filter_attributes (seeded from config.filter_parameters at boot). Assigning filter_attributes
# resets the memoized inspection_filter, so these helpers drive that attribute directly.
def filter_params_setting(user_defined_params, &block)
  original_value = ActiveRecord::Base.filter_attributes
  ActiveRecord::Base.filter_attributes = user_defined_params
  block.call
ensure
  ActiveRecord::Base.filter_attributes = original_value
end

def filter_params_regex_setting(user_defined_params, &block)
  original_value = ActiveRecord::Base.filter_attributes

  filter_params_regex = user_defined_params.map do |key|
    "(?i:#{key})"
  end.join("|")

  ActiveRecord::Base.filter_attributes = [/(?-mix:#{filter_params_regex})/]

  block.call
ensure
  ActiveRecord::Base.filter_attributes = original_value
end
