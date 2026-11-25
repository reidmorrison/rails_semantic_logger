require "rails/generators"
require_relative "../install/install_generator"

module RailsSemanticLogger
  module Generators
    # Adds a local observability stack to a Rails application, for development:
    #
    #   bin/rails generate rails_semantic_logger:observability
    #
    # It writes the stack (compose.observability.yml, the OpenTelemetry Collector config, and Grafana's
    # data source and dashboards under observability/) and a `semantic_logger:traffic` task that sends
    # sample data. It runs rails_semantic_logger:install, which lists each environment's appenders, then
    # adds the OTLP appenders to the development ones, sending the application's logs and metrics to the
    # Collector. It adds nothing to any other environment.
    #
    # The generator knows only the application it runs in and where each file goes. What the stack
    # runs, and the dashboards' queries, belong to the templates.
    class ObservabilityGenerator < ::Rails::Generators::Base
      DEVELOPMENT = "config/environments/development.rb".freeze

      source_root File.expand_path("templates", __dir__)

      desc "Add a local OpenTelemetry Collector, ClickHouse and Grafana stack for the development logs and metrics."

      def create_stack
        copy_file "compose.observability.yml"
        directory "observability"
      end

      def create_traffic_task
        copy_file "lib/tasks/semantic_logger.rake"
      end

      # Writes each environment's appenders explicitly, unless the application declares its own.
      def install
        invoke InstallGenerator, [], observability_hint: false
      end

      def configure_development
        # `rails destroy` must not delete development's settings.
        return if behavior == :revoke

        settings = LoggerSettings.new(development_config)
        if settings.sends_to_otlp?
          say_status :skip, "#{DEVELOPMENT} already sends to OTLP", :yellow
          return
        end

        text = settings.with_appenders_added(after: "\n#{application_setting}") do |indent, name|
          otlp_appenders("#{indent}  ", name)
        end
        # Declarations add up, so the OTLP appenders can have a block of their own.
        text ||= settings.with_block("#{otlp_block}#{application_setting}\n") if declares_appenders?(settings)

        if text
          create_file(DEVELOPMENT, text, force: true, verbose: false)
          say_status :update, DEVELOPMENT
        else
          say_status :error, "#{DEVELOPMENT}: found no appenders block for the OTLP appenders. Add them to its " \
                             "config.rails_semantic_logger.appenders block:\n#{otlp_appenders('  ', 'appenders')}", :red
        end
      end

      def show_next_steps
        say <<~TEXT

          Start the stack, send sample data, then open Grafana:

            docker compose -f compose.observability.yml up -d
            bin/rails semantic_logger:traffic
            open http://localhost:3001

          Every log entry and metric of `bin/rails server` in development now goes to the stack as well.
          This is for development only. For production, see "Production delivery" in the Semantic Logger
          documentation: https://logger.reidmorrison.com/rails.html
        TEXT
      end

      private

      # Returns [String] the name the logs and metrics carry as service.name: the application's module
      # name, underscored, such as "my_shop".
      def application_name
        ::Rails.application.class.module_parent_name.underscore
      end

      def application_setting
        <<~RUBY.lines.map { |line| "  #{line}" }.join
          # The service.name of the logs and metrics sent to the observability stack.
          config.semantic_logger.application = #{application_name.inspect}
        RUBY
      end

      # The OTLP appenders, as lines of the appenders block whose block variable is `name`.
      def otlp_appenders(indent, name)
        <<~RUBY.lines.map { |line| line == "\n" ? line : "#{indent}#{line}" }.join

          # Send the logs and metrics to the local observability stack in compose.observability.yml:
          # the OpenTelemetry Collector on localhost:4318, ClickHouse, and Grafana on http://localhost:3001.
          # Added by `bin/rails generate rails_semantic_logger:observability`.
          #{name}.add(appender: :otlp)
          #{name}.add(metric: :otlp, interval: 10)
        RUBY
      end

      # When the application declares its appenders in config/application.rb, development adds the
      # OTLP appenders to them in a block of its own.
      def otlp_block
        appenders = otlp_appenders("    ", "appenders").delete_prefix("\n")
        "  config.rails_semantic_logger.appenders do |appenders|\n#{appenders}  end\n\n"
      end

      def development_config = read(DEVELOPMENT)

      # Whether development or config/application.rb declares appenders in a form other than an
      # appenders block of development's that it can add to, such as a block with braces.
      def declares_appenders?(settings)
        settings.declares_appenders? || LoggerSettings.new(read(InstallGenerator::APPLICATION)).declares_appenders?
      end

      def read(path)
        file = File.join(destination_root, path)
        File.exist?(file) ? File.read(file) : ""
      end
    end
  end
end
