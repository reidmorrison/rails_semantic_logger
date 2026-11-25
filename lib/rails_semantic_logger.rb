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
    autoload :Metrics, "rails_semantic_logger/rack/metrics"
  end

  module Sidekiq
    autoload :Defaults, "rails_semantic_logger/sidekiq/defaults"
    autoload :JobLogger, "rails_semantic_logger/sidekiq/job_logger"
    autoload :Loggable, "rails_semantic_logger/sidekiq/loggable"
  end

  module SolidQueue
    autoload :LogSubscriber, "rails_semantic_logger/solid_queue/log_subscriber"
  end

  autoload :ApplicationFrame, "rails_semantic_logger/application_frame"
  autoload :SilencedBelowLevel, "rails_semantic_logger/silenced_below_level"
  autoload :Metrics, "rails_semantic_logger/metrics"
  autoload :Appenders, "rails_semantic_logger/appenders"
  autoload :Options, "rails_semantic_logger/options"

  # Deprecator for this gem's deprecations, registered with the application as
  # Rails.application.deprecators[:rails_semantic_logger].
  def self.deprecator
    @deprecator ||= ActiveSupport::Deprecation.new("7.0", "rails_semantic_logger")
  end

  # Whether an entry that the logger logs at the level records a call site: the logger logs at that
  # level, and the level is at or above SemanticLogger.call_site_level. Otherwise there is no reason
  # to look for the entry's call site. The level is any that Semantic Logger accepts, such as :info
  # or ::Logger::INFO.
  def self.call_site?(logger, level)
    SemanticLogger.call_site?(level) && logger.public_send(:"#{SemanticLogger.normalize_level(level)}?")
  end

  # Returns the call site of an entry about the exception that the logger logs at the level, or nil
  # when the entry records none: where the application raised the exception (see
  # ApplicationFrame.in_backtrace), or else false, as for a routing error raised in middleware, or an
  # exception that Rails raised itself, so that the entry records no call site rather than the frame
  # that logged it.
  def self.exception_call_site(exception, backtrace_cleaner, logger, level)
    return unless call_site?(logger, level)

    ApplicationFrame.in_backtrace(exception, backtrace_cleaner).call_site || false
  end

  # Returns [SemanticLogger::CallSite|nil] where the class's instance method is defined, such as a
  # controller's action or a job's #perform, labelled with the class or module that defines it, as
  # Ruby 3.4 labels the method's frames, such as "ArticlesController#index". It is the call site of an
  # entry about that method when none of the application's code is on the stack, as when Rails
  # reports that an action has completed.
  #
  # nil when the class has no such method, as for an action that only renders its template, or when
  # Ruby cannot say where it is defined.
  def self.method_call_site(klass, method_name)
    method     = klass.instance_method(method_name)
    path, line = method.source_location
    return unless path.is_a?(String) && line.is_a?(Integer)

    owner = method.owner.name
    label = owner ? "#{owner}##{method_name}" : method_name.to_s
    SemanticLogger::CallSite.new(path: -path, line: line, label: -label)
  rescue NameError
    nil
  end

  # Record where each entry was logged in development, at every level, unless the application has
  # already chosen a call site level. The engine calls this before the application's configuration
  # is read, so that config/application.rb, config/environments/development.rb or an initializer can
  # choose another level, or turn it off with `config.semantic_logger.call_site_level = nil`.
  def self.record_call_sites_in_development(env)
    SemanticLogger.call_site_level = :trace if env.development? && SemanticLogger.call_site_level.nil?
  end

  # Redact the application's filter parameters (`config.filter_parameters`) from every log entry,
  # by making them Semantic Logger's sensitive keys (see SemanticLogger.sensitive_keys=), unless
  # the application turned this off with `config.rails_semantic_logger.redact_filter_parameters`,
  # or assigned its own `SemanticLogger.sensitive_keys`. An assigned nil cannot be told apart from
  # none, so it does not turn redaction off.
  #
  # Called by the engine once the application has initialized, so that the filters added in
  # `config/initializers/*` apply.
  #
  # Proc filters are left out: Semantic Logger asks the filter about each key by name alone, with
  # no value, and a Proc filter changes the value it is given, rather than saying whether the key
  # is sensitive.
  def self.redact_filter_parameters(config)
    return unless config.rails_semantic_logger.redact_filter_parameters
    return unless SemanticLogger.sensitive_keys.nil?

    filters = config.filter_parameters.reject { |filter| filter.respond_to?(:call) }
    return if filters.empty?

    SemanticLogger.sensitive_keys = ActiveSupport::ParameterFilter.new(filters)
  end

  # Warn that a setting was changed too late to take effect, so the change has no
  # effect. When `config_initializers_too_late` is true (the default), the setting
  # is consumed while the logger is built, *before* `config/initializers/*` is
  # loaded, so that location is called out as too late. When false, the setting is
  # consumed at the end of initialization (`config/initializers/*` still works) and
  # only a change after the application has booted is too late.
  def self.warn_initialized_too_late(setting, config_initializers_too_late: true)
    env       = defined?(Rails) && Rails.respond_to?(:env) ? Rails.env : "<env>"
    locations = "`config/application.rb` or `config/environments/#{env}.rb`"
    locations += " (or a `config/initializers/*` file)" unless config_initializers_too_late
    suffix    = config_initializers_too_late ? "; `config/initializers/*` is loaded too late." : "."
    warn(
      "[rails_semantic_logger] `config.rails_semantic_logger.#{setting}` was set too late to take " \
      "effect, so it has no effect. Set it in #{locations}#{suffix}"
    )
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
  def self.add_server_appenders
    options = Rails.application.config.rails_semantic_logger
    # The default screen appender, when the application declared no appenders of its own.
    if !options.appenders? && !SemanticLogger.appenders.console_output?
      SemanticLogger.add_appender(io: $stdout, formatter: :color)
    end

    options.appenders.server.each do |args, block|
      SemanticLogger.add_appender(**args, &block)
    end
  end

  # Console (REPL) counterpart of .add_server_appenders, used by the `rails console`
  # hook. When the application declared its own appenders, its `add_console`
  # declarations apply; otherwise the default stderr console appender is added.
  def self.add_console_appenders
    options = Rails.application.config.rails_semantic_logger
    # The default console appender, when the application declared no appenders of its own.
    if !options.appenders? && !SemanticLogger.appenders.console_output?
      SemanticLogger.add_appender(io: $stderr, formatter: :color)
    end

    options.appenders.console.each do |args, block|
      SemanticLogger.add_appender(**args, &block)
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
    SemanticLogger.internal_logger = internal_logger if internal_logger
  end

  # Gives the framework that loads as `load_hook`, such as :active_job, the logger, as it loads,
  # unless the application configured one of its own: only while it has Rails' logger.
  def self.give_logger(load_hook, logger)
    ActiveSupport.on_load(load_hook) { self.logger = logger if self.logger.equal?(::Rails.logger) }
  end

  # Swap an existing subscriber with a new one
  def self.swap_subscriber(old_class, new_class, notifier)
    subscribers = ActiveSupport::LogSubscriber.subscribers.grep(old_class)
    subscribers.each { |subscriber| unattach(subscriber) }
    unsubscribe_event_reporter(old_class)

    new_class.attach_to(notifier)
  end

  # Rails 8.2 moved its text log subscribers onto ActiveSupport.event_reporter,
  # so they are no longer attached to ActiveSupport::Notifications.
  def self.unsubscribe_event_reporter(old_class)
    return unless defined?(ActiveSupport::EventReporter::LogSubscriber)
    return unless old_class < ActiveSupport::EventReporter::LogSubscriber

    ActiveSupport.event_reporter.unsubscribe(old_class)
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

  private_class_method :listeners_for, :subscriber_patterns, :unattach, :unsubscribe_event_reporter
end

require("rails_semantic_logger/extensions/mongoid/config") if defined?(Mongoid)
require("rails_semantic_logger/extensions/active_support/logger") if defined?(ActiveSupport::Logger)
require("rails_semantic_logger/extensions/action_view/structured_event_start")
