$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb', __FILE__)
require 'rails/test_help'

#Rails.backtrace_cleaner.remove_silencers!

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'awesome_print'
require 'rails_semantic_logger'

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new

# Rails 5
#
# ActiveRecord::Migrator.migrations_paths = [File.expand_path('../../test/dummy/db/migrate', __FILE__)]
#
# # Filter out Minitest backtrace while allowing backtrace from other libraries
# # to be shown.
# Minitest.backtrace_filter = Minitest::BacktraceFilter.new
#
# # Load fixtures from the engine
# if ActiveSupport::TestCase.respond_to?(:fixture_path=)
#   ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)
#   ActionDispatch::IntegrationTest.fixture_path = ActiveSupport::TestCase.fixture_path
#   ActiveSupport::TestCase.file_fixture_path = ActiveSupport::TestCase.fixture_path + "/files"
#   ActiveSupport::TestCase.fixtures :all
# end
