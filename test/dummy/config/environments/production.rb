Dummy::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  # Full error reports are disabled and caching is turned on
  config.consider_all_requests_local = false
  config.perform_caching             = true
  config.cache_classes               = true
  config.eager_load                  = true

  # Disable Rails's static asset server (Apache or nginx could already do this)
  config.serve_static_files          = true

  # SSL is handled by the load balancer
  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = false

  # See everything in the log (default is :info)
  config.log_level                   = :info

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found)
  config.i18n.fallbacks              = true

  # Send deprecation notices to registered listeners
  config.active_support.deprecation  = :notify

  # Disable colorized logging
  # config.colorize_logging = false
end
