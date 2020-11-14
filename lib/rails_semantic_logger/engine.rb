require "rails"
require "action_controller/log_subscriber"
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

      unless config.rails_semantic_logger.disabled
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
              appender = SemanticLogger::Appender::File.new(
                file_name: path,
                level:     config.log_level,
                formatter: formatter
              )
              appender.name                    = "SemanticLogger"
              SemanticLogger::Processor.logger = appender

              # Check for previous file or stdout loggers
              SemanticLogger.appenders.each { |app| app.formatter = formatter if app.is_a?(SemanticLogger::Appender::File) }
              SemanticLogger.add_appender(file_name: path, formatter: formatter, filter: config.rails_semantic_logger.filter)
            end

            SemanticLogger[Rails]
          rescue StandardError => e
            # If not able to log to file, log to standard error with warning level only
            SemanticLogger.default_level = :warn

            SemanticLogger::Processor.logger = SemanticLogger::Appender::File.new(io: STDERR)
            SemanticLogger.add_appender(io: STDERR)

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
    end

    # Before any initializers run, but after the gems have been loaded
    config.before_initialize do
      unless config.rails_semantic_logger.disabled
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
        Resque.logger        = SemanticLogger[Resque] if defined?(Resque) && Resque.respond_to?(:logger)

        # Replace the Sidekiq logger
        Sidekiq.logger       = SemanticLogger[Sidekiq] if defined?(Sidekiq)

        # Replace the Sidetiq logger
        Sidetiq.logger       = SemanticLogger[Sidetiq] if defined?(Sidetiq)

        # Replace the DelayedJob logger
        if defined?(Delayed::Worker)
          Delayed::Worker.logger = SemanticLogger[Delayed::Worker]
          Delayed::Worker.plugins << RailsSemanticLogger::DelayedJob::Plugin
        end

        # Replace the Bugsnag logger
        Bugsnag.configure { |config| config.logger = SemanticLogger[Bugsnag] } if defined?(Bugsnag)
      end
    end

    # After any initializers run, but after the gems have been loaded
    config.after_initialize do
      unless config.rails_semantic_logger.disabled
        # Replace the Bugsnag logger
        Bugsnag.configure { |config| config.logger = SemanticLogger[Bugsnag] } if defined?(Bugsnag)

        # Rails Patches
        require("rails_semantic_logger/extensions/action_cable/tagged_logger_proxy") if defined?(ActionCable)
        require("rails_semantic_logger/extensions/action_controller/live") if defined?(ActionController::Live)
        require("rails_semantic_logger/extensions/action_dispatch/debug_exceptions") if defined?(ActionDispatch::DebugExceptions)
        if defined?(ActionView::StreamingTemplateRenderer::Body)
          require("rails_semantic_logger/extensions/action_view/streaming_template_renderer")
        end
        require("rails_semantic_logger/extensions/active_job/logging") if defined?(::ActiveJob)
        require("rails_semantic_logger/extensions/active_model_serializers/logging") if defined?(ActiveModelSerializers)
        require("rails_semantic_logger/extensions/rails/server") if defined?(Rails::Server)

        if config.rails_semantic_logger.semantic
          # Active Job
          if defined?(::ActiveJob)
            # Rails >= 6.1 uses ::ActiveJob::LogSubscriber
            log_klass = defined?(::ActiveJob::Logging::LogSubscriber) ? ::ActiveJob::Logging::LogSubscriber : ::ActiveJob::LogSubscriber
            RailsSemanticLogger.swap_subscriber(
              log_klass,
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
            assets_regex                                    = %r(\A/{0,2}#{config.assets.prefix})
            RailsSemanticLogger::Rack::Logger.logger.filter = ->(log) { log.payload[:path] !~ assets_regex if log.payload }
          end

          # Action View
          RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = :info if config.rails_semantic_logger.rendered
          RailsSemanticLogger.swap_subscriber(
            ::ActionView::LogSubscriber,
            RailsSemanticLogger::ActionView::LogSubscriber,
            :action_view
          )

          # Action Controller
          RailsSemanticLogger.swap_subscriber(
            ::ActionController::LogSubscriber,
            RailsSemanticLogger::ActionController::LogSubscriber,
            :action_controller
          )
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
        Resque.after_fork { |_job| ::SemanticLogger.reopen } if defined?(Resque)

        # Re-open appenders after Spring has forked a process
        Spring.after_fork { |_job| ::SemanticLogger.reopen } if defined?(Spring.after_fork)
      end
    end
  end
end
