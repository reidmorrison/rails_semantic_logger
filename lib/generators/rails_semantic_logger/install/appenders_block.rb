require "erb"
require_relative "logger_settings"

module RailsSemanticLogger
  module Generators
    # The explicit `config.rails_semantic_logger.appenders` block of one environment, as Ruby source.
    #
    # Its active lines create exactly the appenders that Rails Semantic Logger creates when an
    # application declares none: the log file, log/<environment>.log, with the formatter that
    # RailsSemanticLogger.default_file_formatter gives, the screen under `rails server` and Sidekiq,
    # and the screen under `rails console`. Listing them lets the application see, and change, where
    # its logs go. A deployed environment also lists, commented out, the usual alternatives.
    #
    # It carries the deprecated appender options that the application set, as the engine applies them:
    # `format` and `ap_options` become the log file's formatter, `filter` its filter,
    # `add_file_appender = false` comments out the log file, and `console_logger = false` the screen.
    # It lists each appender that the application added with `config.semantic_logger.add_appender`,
    # and, as Rails Semantic Logger did, comments out the screen lines when one of those already
    # writes to the screen.
    class AppendersBlock
      TEMPLATE = File.expand_path("templates/appenders.rb.erb", __dir__)

      # environment: [String] such as "production", from the name of the environment's file.
      # options:     [Hash] the value of each deprecated appender option, by name, as Ruby source (see LoggerSettings).
      # appenders:   [Array<String>] the arguments of each appender the application added itself.
      # colorize:    [true|false] whether colorized logging is on, as `config.colorize_logging` says.
      # screen:      [true|false] whether an appender that stays outside the block, such as one that
      #              config/application.rb adds, already writes to the screen.
      def initialize(environment:, options: {}, appenders: [], colorize: true, screen: false)
        @environment = environment
        @options     = options
        @appenders   = appenders
        @colorize    = colorize
        @screen      = screen
      end

      # Returns [String] the block, indented for the `Rails.application.configure` block of the
      # environment's file, followed by a blank line.
      def to_s
        ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding)
      end

      # Whether every line of the block would be commented out. A block that declares no appender
      # declares nothing, so the engine would create its default appenders instead.
      def empty?
        !file? && !screen? && @appenders.empty?
      end

      private

      attr_reader :environment

      def development? = environment == "development"

      def test? = environment == "test"

      # Any environment other than development and test is deployed, such as production or staging.
      def deployed? = !development? && !test?

      def file? = @options[:add_file_appender] != "false"

      def screen?
        return false if @screen || @options[:console_logger] == "false"

        @appenders.none? { |args| LoggerSettings.screen_appender?(args) }
      end

      def file_arguments
        # Rails.env, as the engine's default log file follows it, also when another environment's file
        # loads this one, such as a staging.rb that starts with `require_relative "production"`.
        arguments = %(file_name: "log/\#{Rails.env}.log", formatter: #{file_formatter})
        arguments += ", filter: #{@options[:filter]}" if @options[:filter]
        arguments
      end

      # The engine formats the log file with `format`, in color with `ap_options` when it is :default.
      def file_formatter
        format = @options[:format]
        return format if format && format != ":default"
        return source(RailsSemanticLogger.default_file_formatter(colorize: @colorize)) unless @options[:ap_options]
        return ":default" unless @colorize

        "{color: {ap: #{@options[:ap_options]}}}"
      end

      # The Ruby source of a formatter: a Hash of Symbols, or a Symbol, written as an application would.
      def source(value)
        case value
        when Hash   then "{#{value.map { |key, item| "#{key}: #{source(item)}" }.join(', ')}}"
        when Symbol then ":#{value}"
        else value.inspect
        end
      end

      # Prefixes the line with a comment marker when the appender is turned off.
      def line(text, active: true) = active ? text : "# #{text}"
    end
  end
end
