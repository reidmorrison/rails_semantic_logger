require "semantic_logger"
require "rails_semantic_logger/extensions/rails/server" if defined?(Rails::Server)
require "rails_semantic_logger/engine"

module RailsSemanticLogger
  module ActionController
    autoload :LogSubscriber, "rails_semantic_logger/action_controller/log_subscriber"
  end

  module ActionMailer
    autoload :LogSubscriber, "rails_semantic_logger/action_mailer/log_subscriber"
  end

  module ActionView
    autoload :LogSubscriber, "rails_semantic_logger/action_view/log_subscriber"
  end

  module ActiveJob
    autoload :LogSubscriber, "rails_semantic_logger/active_job/log_subscriber"
  end

  module ActiveRecord
    autoload :LogSubscriber, "rails_semantic_logger/active_record/log_subscriber"
  end

  module Rack
    autoload :Logger, "rails_semantic_logger/rack/logger"
  end

  module DelayedJob
    autoload :Plugin, "rails_semantic_logger/delayed_job/plugin"
  end

  module Sidekiq
    autoload :Defaults, "rails_semantic_logger/sidekiq/defaults"
    autoload :JobLogger, "rails_semantic_logger/sidekiq/job_logger"
    autoload :Loggable, "rails_semantic_logger/sidekiq/loggable"
  end

  module SolidQueue
    autoload :LogSubscriber, "rails_semantic_logger/solid_queue/log_subscriber"
  end

  autoload :Appenders, "rails_semantic_logger/appenders"
  autoload :Options, "rails_semantic_logger/options"

  # Deprecator used for options that are being phased out in favor of declaring
  # appenders directly (see RailsSemanticLogger::Appenders).
  def self.deprecator
    @deprecator ||= ActiveSupport::Deprecation.new("6.0", "rails_semantic_logger")
  end

  # Add a console (stdout/stderr) appender for the interactive contexts that need
  # one (`rails server`, a rack server, the Rails console, Sidekiq in server mode).
  #
  # Skipped when a console appender already exists (avoids double logging to the
  # screen).
  #
  # When the application has taken over appender configuration via
  # `config.rails_semantic_logger.appenders`, the default appender is not used:
  # instead the appenders it declared for this context are created here
  # (`appenders.add_server` for serving contexts, `appenders.add_console` for the
  # Rails console), or none at all when it declared none. `declared` selects which.
  def self.add_console_appender(io:, formatter: :color, declared: :server)
    return if SemanticLogger.appenders.console_output?

    options = Rails.application.config.rails_semantic_logger
    if options.appenders?
      options.appenders.public_send(declared).each do |args, block|
        SemanticLogger.add_appender(**args, &block)
      end
    else
      SemanticLogger.add_appender(io: io, formatter: formatter)
    end
  end

  # Create the appenders declared via `config.rails_semantic_logger.appenders` with
  # `add_server` (or the default console appender when the application declared no
  # appenders of its own).
  #
  # Called automatically for the server contexts that have a first-party hook
  # (`rails server`, Sidekiq in server mode). App servers without such a hook (bare
  # puma, rackup, Passenger, Unicorn) cannot be detected reliably, so call this from
  # the server's own definitive boot hook instead of relying on a guess. Example,
  # in `config/puma.rb`:
  #
  #   on_booted { RailsSemanticLogger.add_server_appenders }
  #
  # Idempotent: skipped when a console appender already exists.
  def self.add_server_appenders
    add_console_appender(io: $stdout, declared: :server)
  end

  # Console (REPL) counterpart of .add_server_appenders, used by the `rails console`
  # hook. When the application declared its own appenders, its `add_console`
  # declarations apply; otherwise the deprecated `console_logger` toggle decides
  # whether the default stderr console appender is added.
  def self.add_console_appenders
    options = Rails.application.config.rails_semantic_logger
    if options.appenders?
      add_console_appender(io: $stderr, declared: :console)
    elsif options.console_logger
      add_console_appender(io: $stderr)
    end
  end

  # Create each appender declared via `config.rails_semantic_logger.appenders`.
  # The first file appender (if any) becomes the internal logger, so that any
  # failures writing to other appenders are still recorded somewhere durable.
  def self.add_appenders(appenders)
    internal_logger = nil
    appenders.each do |args, block|
      appender = SemanticLogger.add_appender(**args, &block)
      internal_logger ||= appender if appender.is_a?(SemanticLogger::Appender::File)
    end
    SemanticLogger::Processor.logger = internal_logger if internal_logger
  end

  # Swap an existing subscriber with a new one
  def self.swap_subscriber(old_class, new_class, notifier)
    subscribers = ActiveSupport::LogSubscriber.subscribers.select { |s| s.is_a?(old_class) }
    subscribers.each { |subscriber| unattach(subscriber) }

    new_class.attach_to(notifier)
  end

  def self.unattach(subscriber)
    subscriber_patterns(subscriber).each do |pattern|
      listeners_for(ActiveSupport::Notifications.notifier, pattern).each do |sub|
        next unless sub.instance_variable_get(:@delegate) == subscriber

        ActiveSupport::Notifications.unsubscribe(sub)
      end
    end

    ActiveSupport::LogSubscriber.subscribers.delete(subscriber)
  end

  def self.subscriber_patterns(subscriber)
    subscriber.patterns.keys
  end

  def self.listeners_for(notifier, pattern)
    notifier.all_listeners_for(pattern)
  end

  private_class_method :listeners_for, :subscriber_patterns, :unattach
end

require("rails_semantic_logger/extensions/mongoid/config") if defined?(Mongoid)
require("rails_semantic_logger/extensions/active_support/logger") if defined?(ActiveSupport::Logger)

begin
  require "rackup"
rescue LoadError
  # No need to do anything, will fall back to Rack
end
if defined?(Rackup::Server)
  require("rails_semantic_logger/extensions/rackup/server")
elsif defined?(Rack::Server)
  require("rails_semantic_logger/extensions/rack/server")
end
