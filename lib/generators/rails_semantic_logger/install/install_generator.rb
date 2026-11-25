require "rails/generators"
require "ripper"
require_relative "logger_settings"
require_relative "appenders_block"

module RailsSemanticLogger
  module Generators
    # Configures an existing Rails application for Rails Semantic Logger:
    #
    #   bin/rails generate rails_semantic_logger:install
    #
    # In config/application.rb and each config/environments/*.rb it removes the logger settings that
    # Rails Semantic Logger ignores or refuses (see LoggerSettings), then writes into each environment
    # an explicit `config.rails_semantic_logger.appenders` block (see AppendersBlock) that creates the
    # same appenders as before, so that where the logs go is plain to see, and to change.
    #
    # It leaves alone the appenders of an environment that already declares them. When
    # config/application.rb declares them, it writes no environment block at all, since the
    # declarations of every file add up. It writes each file once, and only when the result is valid
    # Ruby, and reports each setting it removed, and each one it left for the application to move.
    #
    # The generator knows the application's files. What to remove belongs to LoggerSettings, and what
    # to write to AppendersBlock.
    class InstallGenerator < ::Rails::Generators::Base
      APPLICATION = "config/application.rb".freeze

      # What it will write to one environment's file: the text, or nil when the file cannot take its
      # appenders, and the cleaning that produced it.
      Plan = Struct.new(:path, :text, :result, :declared, :inherits, keyword_init: true)

      desc "Remove the Rails logger settings that Rails Semantic Logger ignores, and list each " \
           "environment's appenders in config.rails_semantic_logger.appenders."

      # Plans every file before writing any: the appenders that config/application.rb adds move into
      # each environment's block, so only when no file declares appenders and every environment can
      # take its block.
      def install
        # `rails destroy` cannot put back what was removed, and must not delete the settings files.
        return if behavior == :revoke

        @application = LoggerSettings.new(read(APPLICATION))
        declared     = @application.declares_appenders? ||
                       environments.any? { |path| settings(path).declares_appenders? }
        app_result, plans = plan(convert: !declared)
        app_result, plans = plan(convert: false) if !declared && plans.any? { |plan| plan.text.nil? }

        write(APPLICATION, app_result.text, app_result)
        plans.each { |plan| apply(plan, app_result) }
      end

      private

      # Returns the cleaning of config/application.rb, and the plan of each environment.
      def plan(convert:)
        app_result = @application.clean(convert_appenders: convert)
        screen     = LoggerSettings.new(app_result.text).adds_screen_appender?
        [app_result, environments.map { |path| plan_environment(path, app_result, screen) }]
      end

      def plan_environment(path, app_result, screen)
        settings = settings(path)
        declared = @application.declares_appenders? || settings.declares_appenders?
        result   = settings.clean(convert_appenders: !declared)
        return Plan.new(path: path, text: result.text, result: result, declared: true) if declared

        inherits = environment_names - [File.basename(path, ".rb")]
        if settings.loads_environment?(inherits)
          return Plan.new(path: path, text: result.text, result: result, declared: true, inherits: true)
        end

        block = AppendersBlock.new(
          environment: File.basename(path, ".rb"),
          options:     app_result.options.merge(result.options),
          appenders:   app_result.appenders + result.appenders,
          colorize:    !(@application.colorize_logging_off? || settings.colorize_logging_off?),
          screen:      screen || LoggerSettings.new(result.text).adds_screen_appender?
        ).to_s
        text = LoggerSettings.new(result.text).with_block(block)
        Plan.new(path: path, text: text && Ripper.sexp(text) ? text : nil, result: result, declared: false)
      end

      def apply(plan, app_result)
        options   = app_result.options.merge(plan.result.options)
        appenders = app_result.appenders + plan.result.appenders
        if plan.inherits
          skip(plan, "it loads another environment's settings, appenders included",
               plan.result.options, plan.result.appenders)
        elsif plan.declared
          where = settings(plan.path).declares_appenders? ? plan.path : APPLICATION
          skip(plan, "its appenders are declared in #{where}", options, appenders)
        elsif plan.text
          say_status :appenders, plan.path if write(plan.path, plan.text, plan.result)
        else
          say_status :error, "#{plan.path}: left unchanged: found no `.configure do` block to add the appenders to, " \
                             "or adding them would not be valid Ruby", :red
          warn_unconverted(plan.path, options, appenders)
        end
      end

      # Writes the cleaned settings of an environment that gets no appenders block of its own.
      def skip(plan, reason, options, appenders)
        say_status :skip, "#{plan.path}: #{reason}", :yellow
        warn_unconverted(plan.path, options, appenders)
        write(plan.path, plan.text, plan.result)
      end

      # Writes the text, when it changed and is valid Ruby, reporting what was removed, and each setting
      # that was left in place. Returns [String|nil] the text, when it wrote it.
      def write(path, text, result)
        result.left.each do |setting|
          say_status :warn, "#{path}: left in place, move it into the appenders: #{setting.lines.first.strip}", :yellow
        end
        return if text == read(path)

        unless Ripper.sexp(text)
          say_status :error, "#{path}: left unchanged, since the change would not be valid Ruby", :red
          return
        end

        result.removed.each { |line| say_status :remove, "#{path}: #{line.strip}", :red }
        create_file(path, text, force: true, verbose: false)
        text
      end

      # The deprecated appender options and the added appenders cannot be carried into appenders that the application
      # declares itself.
      def warn_unconverted(path, options, appenders)
        return if options.empty? && appenders.empty?

        settings = options.keys.map { |name| "rails_semantic_logger.#{name}" } +
                   appenders.map { |args| "add_appender(#{args})" }
        say_status :warn, "#{path}: carry these into its appenders: #{settings.join(', ')}", :yellow
      end

      def settings(path)
        LoggerSettings.new(read(path))
      end

      def environment_names = environments.map { |path| File.basename(path, ".rb") }

      def environments
        Dir[File.join(destination_root, "config/environments/*.rb")].map do |path|
          path.delete_prefix("#{destination_root}/")
        end.sort
      end

      def read(path)
        file = File.join(destination_root, path)
        File.exist?(file) ? File.read(file) : ""
      end
    end
  end
end
