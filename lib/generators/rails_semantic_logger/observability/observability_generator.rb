require "rails/generators"

module RailsSemanticLogger
  module Generators
    # Adds a local observability stack to a Rails application, for development:
    #
    #   bin/rails generate rails_semantic_logger:observability
    #
    # It writes the stack (compose.observability.yml, the OpenTelemetry Collector config, and Grafana's
    # data source and dashboards under observability/), a `semantic_logger:traffic` task that sends
    # sample data, and the development appenders that send the application's logs and metrics to the
    # Collector over OTLP. It never touches the configuration of any other environment.
    #
    # The generator knows only the application it runs in and where each file goes. What the stack
    # runs, and the dashboards' queries, belong to the templates.
    class ObservabilityGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Add a local OpenTelemetry Collector, ClickHouse and Grafana stack for the development logs and metrics."

      def create_stack
        copy_file "compose.observability.yml"
        directory "observability"
      end

      def create_traffic_task
        copy_file "lib/tasks/semantic_logger.rake"
      end

      def configure_development
        if development_config.include?("appender: :otlp")
          say_status :skip, "config/environments/development.rb already sends to OTLP", :yellow
          return
        end

        environment(development_appenders, env: "development")
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

      def development_appenders
        "#{<<~RUBY.lines.map { |line| "  #{line}" }.join}\n"
          # Send the logs and metrics to the local observability stack in compose.observability.yml:
          # the OpenTelemetry Collector on localhost:4318, ClickHouse, and Grafana on http://localhost:3001.
          # Added by `bin/rails generate rails_semantic_logger:observability`.
          config.semantic_logger.application = #{application_name.inspect}
          config.rails_semantic_logger.appenders do |appenders|
          #{default_appenders}  appenders.add(appender: :otlp)
            appenders.add(metric: :otlp, interval: 10)
          end
        RUBY
      end

      # Declaring any appender replaces Rails Semantic Logger's default ones, so declare them again,
      # unless the application already declares its own.
      def default_appenders
        return "" if declares_appenders?

        <<~RUBY.lines.map { |line| "  #{line}" }.join
          appenders.add(file_name: "log/development.log", formatter: :color)
          appenders.add_server
          appenders.add_console
        RUBY
      end

      def declares_appenders?
        %w[config/application.rb config/environments/development.rb].any? do |path|
          file = File.join(destination_root, path)
          File.exist?(file) && File.read(file).include?("rails_semantic_logger.appenders")
        end
      end

      def development_config
        file = File.join(destination_root, "config/environments/development.rb")
        File.exist?(file) ? File.read(file) : ""
      end
    end
  end
end
