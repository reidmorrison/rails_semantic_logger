require "rails"
require "rails_semantic_logger/options"

module RailsSemanticLogger
  class Engine < ::Rails::Engine
    # Make the SemanticLogger config available in the Rails application config
    #
    # Example: Add the MongoDB logging appender in the Rails environment
    #          initializer in file config/environments/development.rb
    #
    #   Rails::Application.configure do
    #     # Add the MongoDB logger appender only once Rails is initialized
    #     config.after_initialize do
    #       appender = SemanticLogger::Appender::Mongo.new(
    #         uri: 'mongodb://127.0.0.1:27017/test'
    #       )
    #       config.semantic_logger.add_appender(appender: appender)
    #     end
    #   end
    config.semantic_logger = ::SemanticLogger

    config.rails_semantic_logger = RailsSemanticLogger::Options.new

    # Clean the backtraces of logged exceptions with the application's backtrace cleaner, as Rails'
    # own log does: only the application's frames, relative to Rails.root, honoring the silencers in
    # config/initializers/backtrace_silencers.rb, and every frame when BACKTRACE is set.
    #
    # Assigned before the application's configuration is read, so that the application can choose
    # another cleaner, or none, with `config.semantic_logger.backtrace_cleaner = ...` in
    # config/application.rb or config/environments/*.rb.
    #
    # In development, also record where each entry was logged, at every level: the file, line, and
    # method of the code behind it. Assigned before the application's configuration is read, so that
    # the application can choose another level, or turn it off, with
    # `config.semantic_logger.call_site_level = nil` in config/application.rb,
    # config/environments/development.rb, or an initializer.
    config.before_configuration do
      ::SemanticLogger.backtrace_cleaner = ::Rails.backtrace_cleaner
      RailsSemanticLogger.record_call_sites_in_development(::Rails.env)
    end

    # Initialize SemanticLogger. In a Rails environment it will automatically
    # insert itself above the configured rails logger to add support for its
    # additional features

    # Register this gem's deprecator with the application so that the standard Rails
    # deprecation settings govern it: `config.active_support.report_deprecations`,
    # `config.active_support.deprecation`, and
    # `Rails.application.deprecators[:rails_semantic_logger]`. Rails' own
    # `active_support.deprecation_behavior` initializer only reaches deprecators in
    # that collection.
    #
    # Runs before the environment file is read so that an application can also reach
    # the deprecator by name from `config/environments/*.rb`.
    initializer "rails_semantic_logger.deprecator", before: :load_environment_config do |app|
      app.deprecators[:rails_semantic_logger] = RailsSemanticLogger.deprecator
    end

    # Replace Rails logger initializer
    Rails::Application::Bootstrap.initializers.delete_if { |i| i.name == :initialize_logger }

    initializer :initialize_logger, group: :all do
      config = Rails.application.config

      # Set the default log level based on the Rails config
      SemanticLogger.default_level = config.log_level

      if defined?(Rails::Rack::Logger) && config.rails_semantic_logger.semantic
        config.middleware.swap(Rails::Rack::Logger, RailsSemanticLogger::Rack::Logger, config.log_tags)
      end

      # Time every request for http.server.request.duration. First in the stack, so that it sees every
      # request, and since an application can delete any other middleware.
      if config.rails_semantic_logger.metrics
        RailsSemanticLogger::Metrics.declare_dimension_keys
        config.middleware.unshift(RailsSemanticLogger::Rack::Metrics)

        # The metrics of each Rails component, recorded whatever is logged. Decided here, with the
        # middleware, so that the setting is read once, when the logger is initialized.
        solid_queue = config.rails_semantic_logger.replace_solid_queue_logger
        config.after_initialize { RailsSemanticLogger::Metrics.attach(solid_queue: solid_queue) }
      end

      # Existing loggers are ignored because servers like trinidad supply their
      # own file loggers which would result in duplicate logging to the same log file
      Rails.logger = config.logger =
        begin
          # The appenders the application declared, if any.
          if config.rails_semantic_logger.appenders?
            RailsSemanticLogger.add_appenders(config.rails_semantic_logger.appenders)
          end

          if config.rails_semantic_logger.default_appenders?
            # The default file appender, log/<environment>.log, in color unless the application turned
            # colorized logging off. Created after the declared ones, so that it is the internal logger.
            path = config.paths["log"].first
            FileUtils.mkdir_p(File.dirname(path))

            formatter = config.colorize_logging == false ? :default : {color: {ap: {multiline: false}}}

            # Set internal logger to log to file only, in case another appender experiences errors during writes
            appender                       = SemanticLogger::Appender::File.new(path, formatter: formatter)
            appender.name                  = "SemanticLogger"
            SemanticLogger.internal_logger = appender

            SemanticLogger.add_appender(file_name: path, formatter: formatter)
          end

          SemanticLogger[Rails]
        rescue StandardError => e
          # If unable to create the appenders, log to standard error with warning level only
          SemanticLogger.default_level = :warn

          SemanticLogger.internal_logger = SemanticLogger::Appender::IO.new($stderr)
          SemanticLogger.add_appender(io: $stderr)

          message =
            if path
              "Rails Error: Unable to access log file. Please ensure that #{path} exists and is chmod 0666."
            else
              "Rails Error: Unable to create the configured appenders."
            end
          logger = SemanticLogger[Rails]
          logger.warn(
            "#{message} The log level has been raised to WARN and the output directed to STDERR " \
            "until the problem is fixed.",
            e
          )
          logger
        end

      # Logger and init-time appenders are now built; settings read above no
      # longer take effect, so flag late changes (e.g. from config/initializers).
      config.rails_semantic_logger.logger_initialized!

      # Replace Rails loggers
      %i[active_record action_controller action_mailer action_view].each do |name|
        ActiveSupport.on_load(name) { include SemanticLogger::Loggable }
      end
      ActiveSupport.on_load(:action_cable) { self.logger = SemanticLogger[::ActionCable] }

      # The cache store has no logger: give it one of its own name, through which its entries are logged
      # and its metrics recorded. Rails logs a line for every cache operation at :debug once a store has
      # a logger, which this one logs at :trace, so that they appear only when asked for, as they did
      # not before; its errors are logged as they are.
      ActiveSupport::Cache::Store.logger ||= SemanticLogger::DebugAsTraceLogger.new("ActiveSupport::Cache::Store")
    end

    # Rails gives Action Controller and Active Job its own logger as each loads, from hooks that its
    # initializers register: Action Controller's `action_controller.set_configs`, and Active Job's
    # `active_job.logger`, whose logger `active_job.set_configs` replaces by one the application
    # configured. Give each a logger of its own name instead, from a hook registered after those, so
    # that it runs after them, and before the application's initializers: the one instance through
    # which its entries are logged, whose level silences them, and its metrics recorded. Named by a
    # String, and set as each loads, so that no framework is loaded before the application has
    # initialized. Action Controller's API controllers share it.
    initializer "rails_semantic_logger.action_controller_logger",
                after: "action_controller.set_configs", before: :load_config_initializers do
      RailsSemanticLogger.give_logger(:action_controller, SemanticLogger["ActionController::Base"])
    end

    initializer "rails_semantic_logger.active_job_logger",
                after: "active_job.set_configs", before: :load_config_initializers do
      RailsSemanticLogger.give_logger(:active_job, SemanticLogger["ActiveJob::Base"])
    end

    # Before any initializers run, but after the gems have been loaded
    config.before_initialize do
      if config.respond_to?(:assets) && defined?(Rails::Rack::Logger) && config.rails_semantic_logger.semantic
        config.rails_semantic_logger.quiet_assets = true if config.assets.quiet

        # Otherwise Sprockets can't find the Rails::Rack::Logger middleware
        config.assets.quiet = false
      end

      # Replace the Mongo Loggers
      Mongoid.logger       = SemanticLogger[Mongoid] if defined?(Mongoid)
      Moped.logger         = SemanticLogger[Moped] if defined?(Moped)
      Mongo::Logger.logger = SemanticLogger[Mongo] if defined?(Mongo::Logger)

      # Replace the Resque Logger
      Resque.logger = SemanticLogger[Resque] if defined?(Resque) && Resque.respond_to?(:logger=)

      # Replace the Sidekiq logger
      if config.rails_semantic_logger.replace_sidekiq_logger && defined?(::Sidekiq)
        ::Sidekiq.configure_client do |config|
          config.logger = ::SemanticLogger[::Sidekiq]
        end

        ::Sidekiq.configure_server do |config|
          config.logger       = ::SemanticLogger[::Sidekiq]
          config[:job_logger] = RailsSemanticLogger::Sidekiq::JobLogger
          RailsSemanticLogger::Sidekiq::JobLogger.metrics = Rails.application.config.rails_semantic_logger.metrics

          # The declared server appenders, and the default screen appender (see .add_server_appenders)
          RailsSemanticLogger.add_server_appenders

          # Replace default error handler when present
          existing = RailsSemanticLogger::Sidekiq::Defaults.delete_default_error_handler(config.error_handlers)
          config.error_handlers << RailsSemanticLogger::Sidekiq::Defaults::ERROR_HANDLER if existing
        end

        ::Sidekiq::Job.singleton_class.prepend(RailsSemanticLogger::Sidekiq::Loggable)
      end

      # Replace the SolidQueue logger
      if config.rails_semantic_logger.replace_solid_queue_logger &&
         defined?(::SolidQueue) && ::SolidQueue.respond_to?(:logger=)
        ::SolidQueue.logger = SemanticLogger[::SolidQueue]
      end

      # Replace the Sidetiq logger
      Sidetiq.logger = SemanticLogger[Sidetiq] if defined?(Sidetiq) && Sidetiq.respond_to?(:logger=)

      # Replace the DelayedJob logger
      Delayed::Worker.logger = SemanticLogger[Delayed::Worker] if defined?(Delayed::Worker)

      # Replace the Bugsnag logger
      Bugsnag.configure(false) { |config| config.logger = SemanticLogger[Bugsnag] } if defined?(Bugsnag)

      # Set the IOStreams PGP logger
      if defined?(IOStreams)
        if IOStreams.respond_to?(:logger=)
          IOStreams.logger = SemanticLogger[IOStreams]
        else
          # Older IOStreams versions
          IOStreams::Pgp.logger = SemanticLogger[IOStreams::Pgp]
        end
      end
    end

    # Redact the application's filter parameters from every log entry. Not before now, since
    # config/initializers/filter_parameter_logging.rb adds to them. Registered before the hook below,
    # so that it runs first.
    config.after_initialize do
      RailsSemanticLogger.redact_filter_parameters(Rails.application.config)
    end

    # After any initializers run, but after the gems have been loaded
    config.after_initialize do
      config = Rails.application.config

      # Replace the Bugsnag logger
      Bugsnag.configure(false) { |bugsnag_config| bugsnag_config.logger = SemanticLogger[Bugsnag] } if defined?(Bugsnag)

      # Rails Patches
      require("rails_semantic_logger/extensions/action_cable/tagged_logger_proxy") if defined?(::ActionCable)
      require("rails_semantic_logger/extensions/action_controller/live") if defined?(::ActionController::Live)
      if defined?(::ActionDispatch::DebugExceptions)
        require("rails_semantic_logger/extensions/action_dispatch/debug_exceptions")
      end
      if defined?(::ActionView::StreamingTemplateRenderer::Body)
        require("rails_semantic_logger/extensions/action_view/streaming_template_renderer")
      end
      require("rails_semantic_logger/extensions/active_job/logging") if defined?(::ActiveJob)
      require("rails_semantic_logger/extensions/active_model_serializers/logging") if defined?(::ActiveModelSerializers)

      if config.rails_semantic_logger.semantic
        # Active Job
        if defined?(::ActiveJob)
          require "active_job/log_subscriber"
          RailsSemanticLogger.swap_subscriber(
            ::ActiveJob::LogSubscriber,
            RailsSemanticLogger::ActiveJob::LogSubscriber,
            :active_job
          )
        end

        # Active Record
        if defined?(::ActiveRecord)
          require "active_record/log_subscriber"

          RailsSemanticLogger.swap_subscriber(
            ::ActiveRecord::LogSubscriber,
            RailsSemanticLogger::ActiveRecord::LogSubscriber,
            :active_record
          )
        end

        # Rack
        RailsSemanticLogger::Rack::Logger.started_request_log_level = :info if config.rails_semantic_logger.started

        # Silence asset logging by applying a filter to the Rails logger itself, not any of the appenders.
        if config.rails_semantic_logger.quiet_assets && config.respond_to?(:assets) && config.assets.prefix
          assets_root                                     = config.relative_url_root.to_s + config.assets.prefix
          assets_regex                                    = %r(\A/{0,2}#{assets_root})
          RailsSemanticLogger::Rack::Logger.logger.filter = lambda do |log|
            log.payload[:path] !~ assets_regex if log.payload
          end
        end

        # Action View
        if defined?(::ActionView)
          require "action_view/log_subscriber"

          if config.rails_semantic_logger.rendered
            RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = :info
          end
          RailsSemanticLogger.swap_subscriber(
            ::ActionView::LogSubscriber,
            RailsSemanticLogger::ActionView::LogSubscriber,
            :action_view
          )
        end

        # Action Controller
        if defined?(::ActionController)
          require "action_controller/log_subscriber"

          subscriber                       = RailsSemanticLogger::ActionController::LogSubscriber
          subscriber.action_message_format = config.rails_semantic_logger.action_message_format
          subscriber.processing_log_level  = :info if config.rails_semantic_logger.processing
          RailsSemanticLogger.swap_subscriber(
            ::ActionController::LogSubscriber,
            RailsSemanticLogger::ActionController::LogSubscriber,
            :action_controller
          )
        end

        # Action Mailer
        if defined?(::ActionMailer)
          require "action_mailer/log_subscriber"

          RailsSemanticLogger.swap_subscriber(
            ::ActionMailer::LogSubscriber,
            RailsSemanticLogger::ActionMailer::LogSubscriber,
            :action_mailer
          )
        end

        # SolidQueue
        if config.rails_semantic_logger.replace_solid_queue_logger && defined?(::SolidQueue::LogSubscriber)
          RailsSemanticLogger.swap_subscriber(
            ::SolidQueue::LogSubscriber,
            RailsSemanticLogger::SolidQueue::LogSubscriber,
            :solid_queue
          )
        end
      end

      # Forking frameworks (Passenger, Resque, Spring, SolidQueue, etc.) no longer
      # need explicit reopen hooks: Semantic Logger v5 reopens appenders automatically
      # in the child via a Process._fork / Process.daemon hook. Apps that opt out with
      # `SemanticLogger.reopen_on_fork = false` are responsible for reopening themselves.

      console do |_app|
        # Don't use a background thread for logging
        SemanticLogger.sync!
        # Add a stderr logger when running inside a Rails console unless one has already been added.
        RailsSemanticLogger.add_console_appenders

        # Include where each entry was logged, its file, line, and method, on the entries logged in the
        # console. Unlike a backtrace, this reads only the frames up to the code that logged the entry.
        SemanticLogger.call_site_level = SemanticLogger.default_level
      end

      # Initialization is complete; the post-init settings have been consumed, so
      # flag changes made after this point (e.g. at runtime) as having no effect.
      config.rails_semantic_logger.fully_initialized!
    end
  end
end
