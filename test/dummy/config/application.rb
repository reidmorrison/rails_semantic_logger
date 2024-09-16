require File.expand_path("boot", __dir__)

require "rails/all"

Bundler.require

module Dummy
  class Application < Rails::Application
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}" if config.respond_to?(:load_defaults)

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [:password]
    config.active_record.sqlite3.represent_boolean_as_integer = true if config.active_record.sqlite3

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Do not swallow errors in after_commit/after_rollback callbacks.
    # config.active_record.raise_in_transactional_callbacks = true

    config.semantic_logger.default_level = :trace
    # Warning: Set to :error or higher in production to avoid performance issues.
    config.semantic_logger.backtrace_level = :trace

    # Test out Amazing Print
    config.rails_semantic_logger.ap_options = {multiline: false, ruby19_syntax: true}
  end
end
