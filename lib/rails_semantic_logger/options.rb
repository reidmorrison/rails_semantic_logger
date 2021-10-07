module RailsSemanticLogger
  # Options for controlling Rails Semantic Logger behavior
  #
  # * Convert Action Controller and Active Record text messages to semantic data
  #
  #     Rails -- Started -- { :ip => "127.0.0.1", :method => "GET", :path => "/dashboards/inquiry_recent_activity" }
  #     UserController -- Completed #index -- { :action => "index", :db_runtime => 54.64, :format => "HTML", :method => "GET", :mongo_runtime => 0.0, :path => "/users", :status => 200, :status_message => "OK", :view_runtime => 709.88 }
  #
  #     config.rails_semantic_logger.semantic = true
  #
  # * Change Rack started message to debug so that it does not appear in production
  #
  #     config.rails_semantic_logger.started = false
  #
  # * Change Processing message to debug so that it does not appear in production
  #
  #     config.rails_semantic_logger.processing = false
  #
  # * Change Action View render log messages to debug so that they do not appear in production
  #
  #     ActionView::Base --   Rendered data/search/_user.html.haml (46.7ms)
  #
  #     config.rails_semantic_logger.rendered = false
  #
  # * Override the Awesome Print options for logging Hash data as text:
  #
  #     Any valid AwesomePrint option for rendering data.
  #     The defaults can changed be creating a `~/.aprc` file.
  #     See: https://github.com/michaeldv/awesome_print
  #
  #     Note: The option :multiline is set to false if not supplied.
  #     Note: Has no effect if Awesome Print is not installed.
  #
  #        config.rails_semantic_logger.ap_options = {multiline: false}
  #
  # * Whether to automatically add an environment specific log file appender.
  #     For Example: 'log/development.log'
  #
  #     Note:
  #       When Semantic Logger fails to log to an appender it logs the error to an
  #       internal logger, which by default writes to STDERR.
  #       Example, change the default internal logger to log to stdout:
  #         SemanticLogger::Processor.logger = SemanticLogger::Appender::IO.new($stdout, level: :warn)
  #
  #       config.rails_semantic_logger.add_file_appender = true
  #
  # * Silence asset logging
  #
  #     config.rails_semantic_logger.quiet_assets = false
  #
  # * Disable automatic logging to stderr when running a Rails console.
  #
  #     config.rails_semantic_logger.console_logger = false
  #
  # * Override the output format for the primary Rails log file.
  #
  #     Valid options:
  #     * :default
  #         Plain text output with no color.
  #     * :color
  #         Plain text output with color.
  #     * :json
  #         JSON output format.
  #     * class
  #
  #     * Proc
  #         A block that will be called to format the output.
  #         It is supplied with the `log` entry and should return the formatted data.
  #
  #     Note:
  #     * `:default` is automatically changed to `:color` if `config.colorize_logging` is `true`.
  #
  #     JSON Example, in `application.rb`:
  #        config.rails_semantic_logger.format = :json
  #
  #     Custom Example, create `app/lib/my_formatter.rb`:
  #
  #       # My Custom colorized formatter
  #       class MyFormatter < SemanticLogger::Formatters::Color
  #         # Return the complete log level name in uppercase
  #         def level
  #           "#{color}log.level.upcase#{color_map.clear}"
  #         end
  #       end
  #
  #      # In application.rb:
  #      config.rails_semantic_logger.format = MyFormatter.new
  #
  #
  #      config.rails_semantic_logger.format = :default
  #
  # * Add a filter to the file logger [Regexp|Proc]
  #   RegExp: Only include log messages where the class name matches the supplied
  #           regular expression. All other messages will be ignored.
  #   Proc: Only include log messages where the supplied Proc returns true.
  #         The Proc must return true or false.
  #
  #     config.rails_semantic_logger.filter = nil
  #
  # * named_tags: *DEPRECATED*
  #   Instead, supply a Hash to config.log_tags
  #   config.rails_semantic_logger.named_tags = nil
  class Options
    attr_accessor :semantic, :started, :processing, :rendered, :ap_options, :add_file_appender,
                  :quiet_assets, :format, :named_tags, :filter, :console_logger

    # Setup default values
    def initialize
      @semantic          = true
      @started           = false
      @processing        = false
      @rendered          = false
      @ap_options        = {multiline: false}
      @add_file_appender = true
      @quiet_assets      = false
      @format            = :default
      @named_tags        = nil
      @filter            = nil
      @console_logger    = true
    end
  end
end
