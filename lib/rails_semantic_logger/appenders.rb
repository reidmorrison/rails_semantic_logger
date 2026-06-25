module RailsSemanticLogger
  # Collects the appenders declared by the application via:
  #
  #   config.rails_semantic_logger.appenders do |appenders|
  #     appenders.add(file_name: "log/#{Rails.env}.log", formatter: :json)
  #     appenders.add_server(io: $stdout, formatter: :color)
  #     appenders.add_console(io: $stderr, formatter: :color)
  #   end
  #
  # When at least one appender is declared this way, Rails Semantic Logger stops
  # building its own default file appender (`format`, `ap_options`, `filter`, and
  # `add_file_appender` no longer apply) and instead creates exactly the appenders
  # declared here.
  #
  # The methods name the *context* in which the appender is created; the
  # destination and formatting are ordinary `SemanticLogger.add_appender` arguments:
  #
  #   #add         - always created, during Rails initialization.
  #   #add_server  - created only when serving requests (`rails server`, a rack
  #                  server, Sidekiq in server mode). Defaults to `$stdout`.
  #   #add_console - created only inside a `rails console` session. Defaults to
  #                  `$stderr` so log output does not tangle with command results.
  #
  # Because each call appends to its context, any appender works in any context,
  # and a context can have several (e.g. a server-only stdout *and* file appender).
  class Appenders
    include Enumerable

    # Destination keys understood by SemanticLogger.add_appender. When none is
    # supplied to #add_server / #add_console, the context's default stream is used.
    DESTINATIONS = %i[io file_name appender logger metric].freeze

    def initialize
      @definitions = []
      @server      = []
      @console     = []
    end

    # Declare an appender. Accepts the same arguments (and optional block) as
    # SemanticLogger.add_appender. Returns self so calls can be chained.
    def add(**args, &block)
      @definitions << [args, block]
      self
    end

    # Declare an appender that is only created when the application is serving
    # requests: `rails server`, a rack server started directly (puma, etc.), or
    # Sidekiq in server mode. It is never created during a non-serving boot (rake
    # tasks, runners, generators), so it only appears where it is useful.
    #
    # Accepts the same arguments (and optional block) as SemanticLogger.add_appender.
    # When no destination is given it defaults to `$stdout`; the formatter defaults
    # to `:color`.
    def add_server(**args, &block)
      @server << [defaults(args, io: $stdout), block]
      self
    end

    # Declare an appender that is only created when running inside a `rails console`
    # session. Identical to #add_server except it defaults to `$stderr`.
    #
    # Accepts the same arguments (and optional block) as SemanticLogger.add_appender.
    def add_console(**args, &block)
      @console << [defaults(args, io: $stderr), block]
      self
    end

    # The appenders declared via #add_server / #add_console, each as
    # [Hash args, Proc|nil block].
    attr_reader :server, :console

    # Yields each #add declaration as [Hash args, Proc|nil block].
    def each(&)
      @definitions.each(&)
    end

    def any?
      @definitions.any? || @server.any? || @console.any?
    end

    private

    # Apply the context default stream and formatter, without overriding a
    # destination (io/file_name/...) the caller already supplied.
    def defaults(args, io:)
      args = {formatter: :color}.merge(args)
      args[:io] = io unless DESTINATIONS.any? { |key| args.key?(key) }
      args
    end
  end
end
