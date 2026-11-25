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
      # appenders, with the reason, and the cleaning that produced it.
      Plan = Struct.new(:path, :text, :reason, :result, :declared, :inherits, keyword_init: true)

      NO_CONFIGURE = "found no `.configure do` block to add the appenders to, " \
                     "or adding them would not be valid Ruby".freeze
      UNMOVED      = "an appenders block would override or repeat the settings left in place: " \
                     "move them into config.rails_semantic_logger.appenders".freeze
      LOG_PATH     = "it sets config.paths[\"log\"], which its appenders block would read before it is set".freeze
      EMPTY        = "its appenders block would declare no appender, so the engine would create its " \
                     "default appenders instead".freeze

      # Set by the observability generator, which adds the OTLP appenders that the hint points to.
      class_option :observability_hint, type: :boolean, default: true, hide: true,
                                        desc: "Point development's appenders to the observability generator"

      desc "Remove the Rails logger settings that Rails Semantic Logger ignores, and list each " \
           "environment's appenders in config.rails_semantic_logger.appenders."

      # Plans every file before writing any. The deprecated options and appenders of
      # config/application.rb move into each environment's block, so only when no file declares
      # appenders and every environment can take its block; otherwise they stay where they are.
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
        app_result = @application.clean(convert: convert)
        screen     = LoggerSettings.new(app_result.text).adds_screen_appender?
        [app_result, environments.map { |path| plan_environment(path, app_result, screen) }]
      end

      def plan_environment(path, app_result, screen)
        settings = settings(path)
        declared = @application.declares_appenders? || settings.declares_appenders?
        # An environment that loads another one gets that one's appenders, and keeps its own.
        inherits = !declared && settings.loads_environment?(environment_names - [File.basename(path, ".rb")])
        result   = settings.clean(convert: !declared && !inherits)
        if declared || inherits
          return Plan.new(path: path, text: result.text, result: result, declared: true, inherits: inherits)
        end

        plan_block(Plan.new(path: path, result: result, declared: false), settings, app_result, screen)
      end

      # Why the environment cannot take an appenders block, if it cannot: settings that stay in place,
      # in its file or another that it shares, would be overridden by the block, or read too late.
      def unlistable(plan, settings, app_result)
        return UNMOVED if (app_result.unmoved + plan.result.unmoved).any?
        return LOG_PATH if settings.sets_log_path?

        loader, *through = loader_with_own_appenders(plan.path)
        return unless loader

        loads = through.empty? ? "#{loader} loads it" : "#{loader} loads it (through #{through.join(', ')})"
        if settings(loader).sets_log_path?
          return "#{loads}, and sets config.paths[\"log\"] after its appenders block would read it"
        end

        "#{loads}, and an appenders block would override its settings"
      end

      # The environment whose file loads this one's and keeps settings that this one's appenders block
      # would override or repeat, if any, such as a staging.rb that requires production.rb and sets
      # `config.rails_semantic_logger.format`.
      # Follows the loads, so that a qa.rb that loads staging.rb, which loads production.rb, counts.
      # Returns [Array<String>|nil] the loader, then the environments it loads this one through, if any,
      # such as ["config/environments/qa.rb", "config/environments/staging.rb"].
      def loader_with_own_appenders(path, seen = [path])
        loaders(path, seen).each do |loader|
          return [loader] if settings(loader).sets_own_appenders?

          chain = loader_with_own_appenders(loader, seen << loader)
          return chain << loader if chain
        end
        nil
      end

      # The other environments whose file loads this one's.
      def loaders(path, seen)
        name = File.basename(path, ".rb")
        (environments - seen).select { |other| settings(other).loads_environment?([name]) }
      end

      # Returns the plan with the text of the environment's file with its appenders block, or with the
      # reason it cannot take one.
      def plan_block(plan, settings, app_result, screen)
        result = plan.result
        reason = unlistable(plan, settings, app_result)
        return plan.tap { plan.reason = reason } if reason

        block = appenders_block(plan, settings, app_result, screen)
        return plan.tap { plan.reason = EMPTY } if block.empty?

        text = LoggerSettings.new(result.text).with_block(block.to_s)
        return plan.tap { plan.reason = NO_CONFIGURE } unless text && Ripper.sexp(text)

        plan.tap { plan.text = text }
      end

      # The environment's appenders block, from its settings and those of config/application.rb.
      def appenders_block(plan, settings, app_result, screen)
        result = plan.result
        AppendersBlock.new(
          environment:   File.basename(plan.path, ".rb"),
          options:       app_result.options.merge(result.options),
          appenders:     app_result.appenders + result.appenders,
          colorize:      !(@application.colorize_logging_off? || settings.colorize_logging_off?),
          screen:        screen || LoggerSettings.new(result.text).adds_screen_appender?,
          observability: options[:observability_hint]
        )
      end

      def apply(plan, app_result)
        if plan.inherits
          skip(plan, "it loads another environment's settings, appenders included")
        elsif plan.declared
          where = settings(plan.path).declares_appenders? ? plan.path : APPLICATION
          skip(plan, "its appenders are declared in #{where}")
        elsif plan.text
          say_status :appenders, plan.path if write(plan.path, plan.text, plan.result)
        else
          say_status :error, "#{plan.path}: left unchanged: #{plan.reason}", :red
          warn_left(plan.path, plan.result)
          warn_unconverted(plan.path, app_result.options.merge(plan.result.options),
                           app_result.appenders + plan.result.appenders)
        end
      end

      # Writes the cleaned settings of an environment that gets no appenders block of its own.
      def skip(plan, reason)
        say_status :skip, "#{plan.path}: #{reason}", :yellow
        write(plan.path, plan.text, plan.result)
      end

      # Writes the text, when it changed and is valid Ruby, reporting what was removed, and each setting
      # that was left in place. Returns [String|nil] the text, when it wrote it.
      def write(path, text, result)
        warn_left(path, result)
        return if text == read(path)

        unless Ripper.sexp(text)
          say_status :error, "#{path}: left unchanged, since the change would not be valid Ruby", :red
          return
        end

        result.removed.each { |line| say_status :remove, "#{path}: #{line.strip}", :red }
        create_file(path, text, force: true, verbose: false)
        text
      end

      def warn_left(path, result)
        result.left.each do |setting|
          say_status :warn, "#{path}: left in place, move it into the appenders: #{setting.lines.first.strip}", :yellow
        end
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
