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
  # * Where logs go
  #
  #     Unless the application declares its own appenders (see #appenders), Rails Semantic Logger
  #     writes to `log/<environment>.log`, in color unless `config.colorize_logging` is false, and to
  #     the screen under `rails server`, Sidekiq in server mode, and `rails console`.
  #
  #     Note:
  #       When Semantic Logger fails to log to an appender it logs the error to an internal logger:
  #       the default log file, or, when the application declares its own appenders, its first file
  #       appender, else STDERR.
  #       Example, change the default internal logger to log to stdout:
  #         SemanticLogger::Processor.logger = SemanticLogger::Appender::IO.new($stdout, level: :warn)
  #
  # * Do not record the Rails metrics, such as `http.server.request.duration`, nor the Sidekiq job
  #   metrics (`sidekiq.queue.duration` and `messaging.process.duration`).
  #
  #     They are named after the OpenTelemetry semantic conventions where one exists, recorded
  #     whatever is logged, and cost almost nothing until a metric appender is added. Set it in
  #     `config/application.rb` or `config/environments/*.rb`, since the request metrics middleware
  #     is added while the logger is initialized.
  #
  #     config.rails_semantic_logger.metrics = false
  #
  # * Silence asset logging
  #
  #     config.rails_semantic_logger.quiet_assets = false
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
  #
  # * Do not redact the application's filter parameters from every log entry.
  #
  #   Rails filters `config.filter_parameters` only from the request parameters that it logs. By
  #   default, Rails Semantic Logger also has Semantic Logger replace the value of every key that
  #   they match with "[FILTERED]" in every log entry: in its payload, named tags, and context, at
  #   any depth, before any appender writes it. Keys are matched by name, both as written and in
  #   snake_case, so `X-Api-Key` is also matched as `x_api_key`. The filters are read once the
  #   application has initialized, so those added in `config/initializers/*`, such as
  #   `config/initializers/filter_parameter_logging.rb`, apply. See `SemanticLogger.sensitive_keys=`.
  #
  #   Note:
  #   * The filters match any key that contains them, so Rails' default filters (:passw, :email,
  #     :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc) also redact
  #     keys such as `max_tokens`, `token_count`, `cache_key`, and `api_key_id`, every `email`, and
  #     the `concurrency_key` of Solid Queue's entries.
  #   * Rails' default filters do not match `Authorization` or `Cookie`; add them to
  #     `config.filter_parameters` to redact those, e.g. `config.filter_parameters += [:authorization]`.
  #   * Active Job `arguments` and Action Mailer `args` are logged as JSON text, which is not
  #     redacted. For a job that takes a secret, leave its arguments out of the log with
  #     `self.log_arguments = false`.
  #   * Proc filters are not applied, since they change values rather than match keys.
  #   * A dotted filter, such as "credit_card.code", only matches a key named that, not a `code` key
  #     nested in `credit_card`, including the "model.attribute" filters that Rails adds for Active
  #     Record encrypted attributes.
  #   * An application that assigns its own `SemanticLogger.sensitive_keys` keeps them. Assigning
  #     nil does not turn redaction off, since it cannot be told apart from never assigning it: use
  #     this option.
  #   * Entries logged before the application has initialized may not be redacted.
  #
  #     config.rails_semantic_logger.redact_filter_parameters = false
  class Options
    # Settings consumed while the logger itself is built, during Rails'
    # `:initialize_logger` initializer. Changing them after that (e.g. from
    # `config/initializers/*`, which Rails loads later) has no effect.
    LOGGER_INIT_SETTINGS = %i[semantic metrics replace_sidekiq_logger replace_solid_queue_logger].freeze

    # Settings consumed as Rails finishes initializing (`config.after_initialize`),
    # which runs *after* `config/initializers/*`. They may still be set there, but
    # changing them after the application has booted has no effect.
    POST_INIT_SETTINGS = %i[
      started processing rendered quiet_assets action_message_format redact_filter_parameters
    ].freeze

    attr_reader(*LOGGER_INIT_SETTINGS, *POST_INIT_SETTINGS)

    LOGGER_INIT_SETTINGS.each do |setting|
      define_method("#{setting}=") do |value|
        warn_if_logger_initialized(setting)
        instance_variable_set(:"@#{setting}", value)
      end
    end

    POST_INIT_SETTINGS.each do |setting|
      define_method("#{setting}=") do |value|
        warn_if_fully_initialized(setting)
        instance_variable_set(:"@#{setting}", value)
      end
    end

    # Setup default values
    def initialize
      @semantic                   = true
      @metrics                    = true
      @started                    = false
      @processing                 = false
      @rendered                   = false
      @quiet_assets               = false
      @action_message_format      = nil
      @replace_sidekiq_logger     = true
      @replace_solid_queue_logger = true
      @redact_filter_parameters   = true
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
    # requests (`rails server`, Sidekiq in server mode; defaults to
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
    # least one appender has been declared, the default file appender and the default
    # screen appenders of `rails server` and `rails console` are no longer created.
    def appenders
      @appenders ||= RailsSemanticLogger::Appenders.new
      if block_given?
        warn_if_logger_initialized(:appenders)
        yield @appenders
      end
      @appenders
    end

    # Whether the application declared its own appenders via #appenders.
    def appenders?
      defined?(@appenders) && @appenders.any?
    end

    # Marks that Rails Semantic Logger has already built its logger and the
    # init-time appenders. Called by the engine at the end of the
    # `:initialize_logger` initializer. After this point, settings that are only
    # read while building those appenders no longer have any effect, so changing
    # them emits a warning (see #warn_if_logger_initialized).
    def logger_initialized!
      @logger_initialized = true
    end

    # Marks that Rails has finished initializing the application (the engine's
    # `config.after_initialize` has run). Called by the engine. After this point,
    # the POST_INIT_SETTINGS have already been consumed, so changing them warns.
    def fully_initialized!
      @fully_initialized = true
    end

    private

    # Warn when an init-time setting is changed after the logger and its
    # appenders have already been built. This is the classic footgun of putting
    # logger configuration in `config/initializers/*`, which Rails loads *after*
    # the logger is initialized, so the change silently has no effect.
    def warn_if_logger_initialized(setting)
      return unless defined?(@logger_initialized) && @logger_initialized

      RailsSemanticLogger.warn_initialized_too_late(setting)
    end

    # Warn when a setting consumed at the end of Rails initialization is changed
    # after the application has already booted. Unlike #warn_if_logger_initialized,
    # `config/initializers/*` is *not* too late for these, so it is not suggested.
    def warn_if_fully_initialized(setting)
      return unless defined?(@fully_initialized) && @fully_initialized

      RailsSemanticLogger.warn_initialized_too_late(setting, config_initializers_too_late: false)
    end
  end
end
