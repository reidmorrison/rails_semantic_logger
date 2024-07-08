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

    # Initialize SemanticLogger. In a Rails environment it will automatically
    # insert itself above the configured rails logger to add support for its
    # additional features

    # Replace Rails logger initializer
    Rails::Application::Bootstrap.initializers.delete_if { |i| i.name == :initialize_logger }

    initializer :initialize_logger, group: :all do
      config = Rails.application.config

      # Set the default log level based on the Rails config
      SemanticLogger.default_level = config.log_level

      if defined?(Rails::Rack::Logger) && config.rails_semantic_logger.semantic
        config.middleware.swap(Rails::Rack::Logger, RailsSemanticLogger::Rack::Logger, config.log_tags)
      end

      # Existing loggers are ignored because servers like trinidad supply their
      # own file loggers which would result in duplicate logging to the same log file
      Rails.logger = config.logger =
        begin
          if config.rails_semantic_logger.add_file_appender
            path = config.paths["log"].first
            FileUtils.mkdir_p(File.dirname(path)) unless File.exist?(File.dirname(path))

            # Add the log file to the list of appenders
            # Use the colorized formatter if Rails colorized logs are enabled
            ap_options = config.rails_semantic_logger.ap_options
            formatter  = config.rails_semantic_logger.format
            formatter  = {color: {ap: ap_options}} if (formatter == :default) && (config.colorize_logging != false)

            # Set internal logger to log to file only, in case another appender experiences errors during writes
            appender                         = SemanticLogger::Appender::File.new(path, formatter: formatter)
            appender.name                    = "SemanticLogger"
            SemanticLogger::Processor.logger = appender

            # Check for previous file or stdout loggers
            SemanticLogger.appenders.each do |app|
              next unless app.is_a?(SemanticLogger::Appender::File) || app.is_a?(SemanticLogger::Appender::IO)

              app.formatter = formatter
            end
            SemanticLogger.add_appender(file_name: path, formatter: formatter, filter: config.rails_semantic_logger.filter)
          end

          SemanticLogger[Rails]
        rescue StandardError => e
          # If not able to log to file, log to standard error with warning level only
          SemanticLogger.default_level = :warn

          SemanticLogger::Processor.logger = SemanticLogger::Appender::IO.new($stderr)
          SemanticLogger.add_appender(io: $stderr)

          logger = SemanticLogger[Rails]
          logger.warn(
            "Rails Error: Unable to access log file. Please ensure that #{path} exists and is chmod 0666. " \
            "The log level has been raised to WARN and the output directed to STDERR until the problem is fixed.",
            e
          )
          logger
        end

      # Replace Rails loggers
      %i[active_record action_controller action_mailer action_view].each do |name|
        ActiveSupport.on_load(name) { include SemanticLogger::Loggable }
      end
      ActiveSupport.on_load(:action_cable) { self.logger = SemanticLogger["ActionCable"] }
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
      Resque.logger        = SemanticLogger[Resque] if defined?(Resque) && Resque.respond_to?(:logger=)

      # Replace the Sidekiq logger
      if defined?(::Sidekiq)
        ::Sidekiq.configure_client do |config|
          config.logger = ::SemanticLogger[::Sidekiq]
        end

        ::Sidekiq.configure_server do |config|
          config.logger = ::SemanticLogger[::Sidekiq]
          if config.respond_to?(:options)
            config.options[:job_logger] = RailsSemanticLogger::Sidekiq::JobLogger
          else
            config[:job_logger] = RailsSemanticLogger::Sidekiq::JobLogger
          end

          # Add back the default console logger unless already added
          SemanticLogger.add_appender(io: $stdout, formatter: :color) unless SemanticLogger.appenders.console_output?

          # Replace default error handler when present
          existing = RailsSemanticLogger::Sidekiq::Defaults.delete_default_error_handler(config.error_handlers)
          config.error_handlers << RailsSemanticLogger::Sidekiq::Defaults::ERROR_HANDLER if existing
        end

        if defined?(::Sidekiq::Job) && (::Sidekiq::VERSION.to_i != 5)
          ::Sidekiq::Job.singleton_class.prepend(RailsSemanticLogger::Sidekiq::Loggable)
        else
          ::Sidekiq::Worker.singleton_class.prepend(RailsSemanticLogger::Sidekiq::Loggable)
        end
      end

      # Replace the Sidetiq logger
      Sidetiq.logger = SemanticLogger[Sidetiq] if defined?(Sidetiq) && Sidetiq.respond_to?(:logger=)

      # Replace the DelayedJob logger
      if defined?(Delayed::Worker)
        Delayed::Worker.logger = SemanticLogger[Delayed::Worker]
        Delayed::Worker.plugins << RailsSemanticLogger::DelayedJob::Plugin
      end

      # Replace the Bugsnag logger
      Bugsnag.configure(false) { |config| config.logger = SemanticLogger[Bugsnag] } if defined?(Bugsnag)

      # Set the IOStreams PGP logger
      IOStreams::Pgp.logger = SemanticLogger["IOStreams::Pgp"] if defined?(IOStreams)
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
        if defined?(::ActiveJob::Logging::LogSubscriber)
          RailsSemanticLogger.swap_subscriber(
            ::ActiveJob::Logging::LogSubscriber,
            RailsSemanticLogger::ActiveJob::LogSubscriber,
            :active_job
          )
        end

        if defined?(::ActiveJob::LogSubscriber)
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
        if config.rails_semantic_logger.quiet_assets && config.assets.prefix
          assets_root                                     = config.relative_url_root.to_s + config.assets.prefix
          assets_regex                                    = %r(\A/{0,2}#{assets_root})
          RailsSemanticLogger::Rack::Logger.logger.filter = ->(log) { log.payload[:path] !~ assets_regex if log.payload }
        end

        # Action View
        if defined?(::ActionView)
          require "action_view/log_subscriber"

          RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = :info if config.rails_semantic_logger.rendered
          RailsSemanticLogger.swap_subscriber(
            ::ActionView::LogSubscriber,
            RailsSemanticLogger::ActionView::LogSubscriber,
            :action_view
          )
        end

        # Action Controller
        if defined?(::ActionController)
          require "action_controller/log_subscriber"

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

        require("rails_semantic_logger/extensions/sidekiq/sidekiq") if defined?(::Sidekiq)
      end

      #
      # Forking Frameworks
      #

      # Passenger provides the :starting_worker_process event for executing
      # code after it has forked, so we use that and reconnect immediately.
      if defined?(PhusionPassenger)
        PhusionPassenger.on_event(:starting_worker_process) do |forked|
          SemanticLogger.reopen if forked
        end
      end

      # Re-open appenders after Resque has forked a worker
      Resque.after_fork { |_job| ::SemanticLogger.reopen } if defined?(Resque.after_fork)

      # Re-open appenders after Spring has forked a process
      Spring.after_fork { |_job| ::SemanticLogger.reopen } if defined?(Spring.after_fork)

      console do |_app|
        # Don't use a background thread for logging
        SemanticLogger.sync!
        # Add a stderr logger when running inside a Rails console unless one has already been added.
        if config.rails_semantic_logger.console_logger && !SemanticLogger.appenders.console_output?
          SemanticLogger.add_appender(io: STDERR, formatter: :color)
        end

        # Include method names on log entries in the console
        SemanticLogger.backtrace_level = SemanticLogger.default_level
      end
    end
  end
end
