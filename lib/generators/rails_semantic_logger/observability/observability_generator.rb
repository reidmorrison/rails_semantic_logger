require "rails/generators"
require_relative "../install/install_generator"
require_relative "observability_settings"

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
      OTLP_KINDS  = %i[logs metrics].freeze

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
        invoke InstallGenerator, [], options.merge(observability_hint: false)
      end

      def configure_development
        # `rails destroy` must not delete development's settings.
        return if behavior == :revoke

        settings = ObservabilitySettings.new(AppendersBlock.without_observability_hint(development_config))
        @missing = missing_otlp(settings)
        if @missing.empty?
          @sends_to_otlp = true
          say_status :skip, "#{DEVELOPMENT} already sends its logs and metrics to OTLP", :yellow
          return
        end

        name = settings.names_application? || application_settings.names_application? ? "" : application_setting
        text = settings.with_appenders_added(after: name.empty? ? "" : "\n#{name}") do |indent, variable|
          otlp_appenders("#{indent}  ", variable)
        end
        # Declarations add up, so the OTLP appenders can have a block of their own.
        text ||= settings.with_block("#{otlp_block}#{name}#{"\n" unless name.empty?}") if declares_appenders?(settings)

        if text
          @sends_to_otlp = true
          create_file(DEVELOPMENT, text, force: true, verbose: false)
          say_status :update, DEVELOPMENT
        elsif options[:pretend]
          # The install step only pretended to write development's block, so there is none to show.
          say_status :update, "#{DEVELOPMENT}: the OTLP appenders, in the appenders block that " \
                              "rails_semantic_logger:install writes, if it writes one"
        else
          say_status :error, "#{DEVELOPMENT}: found no appenders block for the OTLP appenders. Add them to its " \
                             "config.rails_semantic_logger.appenders block:\n#{otlp_appenders('  ', 'appenders')}", :red
        end
      end

      def show_next_steps
        return if behavior == :revoke || options[:pretend]

        unless @sends_to_otlp
          say "\nDevelopment does not send to the stack yet: add the OTLP appenders above, then start it with " \
              "`docker compose -f compose.observability.yml up -d`."
          return
        end

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

      # Returns [Array<Symbol>] the OTLP appenders, of :logs and :metrics, that development or
      # config/application.rb has none of. Says which ones they have only sometimes: another would then
      # send twice, so those are left as they are.
      def missing_otlp(settings)
        always    = settings.sends_to_otlp | application_settings.sends_to_otlp
        mentioned = settings.mentions_otlp | application_settings.mentions_otlp
        sometimes = mentioned - always
        unless sometimes.empty?
          say_status :warn, "#{DEVELOPMENT} sends its #{sometimes.join(' and ')} to OTLP only sometimes: " \
                            "left as they are, since another OTLP appender would send them twice", :yellow
        end
        OTLP_KINDS - mentioned
      end

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
        <<~RUBY.lines.map { |line| line == "\n" ? line : "#{indent}#{line}" }.join.

          # Send the #{(@missing || OTLP_KINDS).join(' and ')} to the local observability stack in compose.observability.yml:
          # the OpenTelemetry Collector on localhost:4318, ClickHouse, and Grafana on http://localhost:3001.
          # Added by `bin/rails generate rails_semantic_logger:observability`.
        RUBY
          then { |comment| comment + otlp_lines(indent, name) }
      end

      # The OTLP appenders that development does not send to yet: all of them, unless it already sends
      # its logs or its metrics.
      def otlp_lines(indent, name)
        lines = {logs: "#{name}.add(appender: :otlp)\n", metrics: "#{name}.add(metric: :otlp, interval: 10)\n"}
        (@missing || OTLP_KINDS).map { |kind| "#{indent}#{lines.fetch(kind)}" }.join
      end

      # When the application declares its appenders in config/application.rb, development adds the
      # OTLP appenders to them in a block of its own.
      def otlp_block
        appenders = otlp_appenders("    ", "appenders").delete_prefix("\n")
        "  config.rails_semantic_logger.appenders do |appenders|\n#{appenders}  end\n\n"
      end

      def development_config = read(DEVELOPMENT)

      # Whether development or config/application.rb always declares appenders in a form other than an
      # appenders block of development's that it can add to, such as a block with braces, so that a block
      # of only the OTLP appenders adds to them. Not when they are declared only under a condition: the
      # OTLP block would turn off the default appenders where it does not hold.
      def declares_appenders?(settings)
        settings.always_declares_appenders? || application_settings.always_declares_appenders?
      end

      def application_settings = ObservabilitySettings.new(read(InstallGenerator::APPLICATION))

      def read(path)
        file = File.join(destination_root, path)
        File.exist?(file) ? File.read(file) : ""
      end
    end
  end
end
