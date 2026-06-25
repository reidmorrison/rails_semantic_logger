module RailsSemanticLogger
  # Options for controlling Rails Semantic Logger behavior
  #
  # * Convert Action Controller and Active Record text messages to semantic data
  #
  #     Rails -- Started -- { :ip => "127.0.0.1", :method => "GET", :path => "/dashboards/inquiry_recent_activity" }
  # rubocop:disable Layout/LineLength
  #     UserController -- Completed #index -- { :action => "index", :db_runtime => 54.64, :format => "HTML", :method => "GET", :mongo_runtime => 0.0, :path => "/users", :status => 200, :status_message => "OK", :view_runtime => 709.88 }
  # rubocop:enable Layout/LineLength
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
  # * Override the Amazing Print options for logging Hash data as text:
  #
  #     Any valid Amazing Print option for rendering data.
  #     The defaults can changed be creating a `~/.aprc` file.
  #     See: https://github.com/amazing-print/amazing_print
  #
  #     Note: The option :multiline is set to false if not supplied.
  #     Note: Has no effect if Amazing Print is not installed.
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
  #   DEPRECATED: declare appenders via #appenders instead. Declaring any appender there already
  #   replaces the default file appender, so this flag is no longer needed:
  #     config.rails_semantic_logger.appenders { |appenders| appenders.add(file_name: ...) }
  #
  # * Silence asset logging
  #
  #     config.rails_semantic_logger.quiet_assets = false
  #
  # * Disable automatic logging to stderr when running a Rails console.
  #
  #     config.rails_semantic_logger.console_logger = false
  #
  #   DEPRECATED: declare a console appender explicitly via #appenders instead, or
  #   declare none to disable it:
  #     config.rails_semantic_logger.appenders { |appenders| appenders.add_console(...) }
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
  #
  # * Change the message format of Action Controller action.
  #   A block that will be called to format the message.
  #   It is supplied with the `message` and `payload` and should return the formatted data.
  #
  #     config.rails_semantic_logger.action_message_format = -> (message, payload) do
  #       "#{message} - #{payload[:controller]}##{payload[:action]}"
  #     end
  #
  # * Do not replace the Sidekiq logger with a Semantic Logger logger.
  #
  #     config.rails_semantic_logger.replace_sidekiq_logger = false
  #
  # * Do not replace the SolidQueue logger / log subscriber.
  #
  #     config.rails_semantic_logger.replace_solid_queue_logger = false
  class Options
    attr_accessor :semantic, :started, :processing, :rendered,
                  :quiet_assets, :named_tags, :action_message_format,
                  :replace_sidekiq_logger, :replace_solid_queue_logger

    # DEPRECATED: configure these on the appender instead, via #appenders.
    attr_reader :ap_options, :format, :filter, :console_logger, :add_file_appender

    # Setup default values
    def initialize
      @semantic                   = true
      @started                    = false
      @processing                 = false
      @rendered                   = false
      @ap_options                 = {multiline: false}
      @add_file_appender          = true
      @quiet_assets               = false
      @format                     = :default
      @named_tags                 = nil
      @filter                     = nil
      @console_logger             = true
      @action_message_format      = nil
      @replace_sidekiq_logger     = true
      @replace_solid_queue_logger = true
    end

    # Declare the appenders for Rails Semantic Logger to create, replacing the
    # default file appender:
    #
    #   config.rails_semantic_logger.appenders do |appenders|
    #     appenders.add(file_name: "log/#{Rails.env}.log", formatter: :json)
    #     appenders.add_server(io: $stdout, formatter: :color)
    #     appenders.add_console(io: $stderr, formatter: :color)
    #   end
    #
    # The method names the context in which the appender is created; the destination
    # is an ordinary `SemanticLogger.add_appender` argument. Use `add` for an
    # appender that is always created, `add_server` for one created only when serving
    # requests (`rails server`, a rack server, Sidekiq in server mode; defaults to
    # `$stdout`), and `add_console` for one created only inside a `rails console`
    # session (defaults to `$stderr`). Any appender works in any context, so a
    # context may declare several (e.g. a server-only stdout and file appender).
    #
    # `add_server` appenders are created automatically under `rails server` and
    # Sidekiq in server mode. App servers without a first-party hook (bare puma,
    # rackup, Passenger, Unicorn) are not detected; create them from the server's
    # own boot hook instead, e.g. in `config/puma.rb`:
    #
    #   on_booted { RailsSemanticLogger.add_server_appenders }
    #
    # Returns the underlying RailsSemanticLogger::Appenders collection. When at
    # least one appender has been declared, the default file appender (and the
    # `format`, `ap_options`, `filter`, and `add_file_appender` options) is no
    # longer used.
    def appenders
      @appenders ||= RailsSemanticLogger::Appenders.new
      yield @appenders if block_given?
      @appenders
    end

    # Whether the application declared its own appenders via #appenders.
    def appenders?
      defined?(@appenders) && @appenders.any?
    end

    def ap_options=(value)
      deprecate_appender_option(:ap_options)
      @ap_options = value
    end

    def format=(value)
      deprecate_appender_option(:format)
      @format = value
    end

    def filter=(value)
      deprecate_appender_option(:filter)
      @filter = value
    end

    def console_logger=(value)
      deprecate_appender_option(:console_logger, via: "appenders.add_console(...)")
      @console_logger = value
    end

    def add_file_appender=(value)
      deprecate_appender_option(:add_file_appender)
      @add_file_appender = value
    end

    private

    def deprecate_appender_option(option, via: "appenders.add(...)")
      RailsSemanticLogger.deprecator.warn(
        "`config.rails_semantic_logger.#{option}=` is deprecated and will be removed in a future release. " \
        "Declare the destination and formatting directly instead, via " \
        "`config.rails_semantic_logger.appenders { |appenders| #{via} }`."
      )
    end
  end
end
