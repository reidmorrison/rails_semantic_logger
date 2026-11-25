require_relative "../test_helper"
require "ripper"
require "generators/rails_semantic_logger/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests RailsSemanticLogger::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  APPLICATION = <<~RUBY.freeze
    module Shop
      class Application < Rails::Application
        config.load_defaults 8.1
      end
    end
  RUBY

  # As Rails 8.1 writes it.
  PRODUCTION = <<~RUBY.freeze
    Rails.application.configure do
      # Settings specified here will take precedence over those in config/application.rb.

      config.eager_load = true

      # Log to STDOUT with the current request id as a default log tag.
      config.log_tags = [ :request_id ]
      config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

      # Change to "debug" to log everything (including potentially personally-identifiable information!).
      config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
    end
  RUBY

  # As Rails 7.2 writes it.
  PRODUCTION_7_2 = <<~RUBY.freeze
    Rails.application.configure do
      config.eager_load = true

      # Log to STDOUT by default
      config.logger = ActiveSupport::Logger.new(STDOUT)
        .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
        .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

      # Prepend all log lines with the following tags.
      config.log_tags = [ :request_id ]
    end
  RUBY

  # As Rails 6 and 7.0 write it.
  PRODUCTION_7_0 = <<~RUBY.freeze
    Rails.application.configure do
      config.eager_load = true

      # Use default logging formatter so that PID and timestamp are not suppressed.
      config.log_formatter = ::Logger::Formatter.new

      # Use a different logger for distributed setups.
      # require "syslog/logger"
      # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new 'app-name')

      if ENV["RAILS_LOG_TO_STDOUT"].present?
        logger           = ActiveSupport::Logger.new(STDOUT)
        logger.formatter = config.log_formatter
        config.logger    = ActiveSupport::TaggedLogging.new(logger)
      end

      config.active_record.dump_schema_after_migration = false
    end
  RUBY

  ENVIRONMENT = <<~RUBY.freeze
    Rails.application.configure do
      # Settings specified here will take precedence over those in config/application.rb.

      config.enable_reloading = true
    end
  RUBY

  setup do
    prepare_destination
    write("config/application.rb", APPLICATION)
    write("config/environments/development.rb", ENVIRONMENT)
    write("config/environments/test.rb", ENVIRONMENT)
    write("config/environments/production.rb", PRODUCTION)
  end

  test "removes config.logger, keeps the log tags and level, and rewords Rails' comment" do
    run_generator

    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "config.logger"
      assert_includes config, "# Tag every log entry with the current request id.\n  config.log_tags = [ :request_id ]"
      assert_includes config, 'config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")'
      assert_valid_ruby config
    end
  end

  test "lists in each environment the appenders that Rails Semantic Logger created by default" do
    run_generator

    %w[development test production].each do |environment|
      assert_file "config/environments/#{environment}.rb" do |config|
        assert_includes config, "config.rails_semantic_logger.appenders do |appenders|"
        assert_includes config,
                        "    appenders.add(file_name: config.paths[\"log\"].first, " \
                        "formatter: {color: {ap: {multiline: false}}})\n"
        assert_includes config, "    appenders.add_server(io: $stdout, formatter: :color)\n"
        assert_includes config, "    appenders.add_console(io: $stderr, formatter: :color)\n"
        assert_valid_ruby config
      end
    end
  end

  test "puts the appenders after the comment that Rails writes first" do
    run_generator

    assert_file "config/environments/development.rb",
                /configure do\n  # Settings specified here.*\n\n  # Where the logs go\./
  end

  test "lists the usual alternatives, commented out, in a deployed environment only" do
    write("config/environments/staging.rb", ENVIRONMENT)

    run_generator

    %w[production staging].each do |environment|
      assert_file "config/environments/#{environment}.rb" do |config|
        assert_includes config, "#   appenders.add(io: $stdout, formatter: :json)"
        assert_includes config, "#   appenders.add(appender: :otlp)"
        assert_includes config, "#   appenders.add(metric: :otlp)"
      end
    end
  end

  test "points development, only, to the observability generator, and lists no alternatives there" do
    run_generator

    assert_file "config/environments/development.rb" do |config|
      refute_includes config, "formatter: :json"
      assert_includes config, "#   bin/rails generate rails_semantic_logger:observability"
    end
    assert_file "config/environments/test.rb" do |config|
      refute_includes config, "formatter: :json"
      refute_includes config, "observability"
    end
  end

  test "removes the multi-line config.logger of Rails 7.2, and its comment" do
    write("config/environments/production.rb", PRODUCTION_7_2)

    run_generator

    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "config.logger"
      refute_includes config, ".tap"
      refute_includes config, "Log to STDOUT by default"
      assert_includes config, "# Prepend all log lines with the following tags.\n  config.log_tags = [ :request_id ]"
      assert_valid_ruby config
    end
  end

  test "removes the log formatter, the RAILS_LOG_TO_STDOUT block and the Syslog example of Rails 7.0" do
    write("config/environments/production.rb", PRODUCTION_7_0)

    run_generator

    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "log_formatter"
      refute_includes config, "RAILS_LOG_TO_STDOUT"
      refute_includes config, "Syslog"
      refute_includes config, "PID and timestamp"
      refute_includes config, "distributed setups"
      assert_includes config, "config.active_record.dump_schema_after_migration = false"
      refute_match(/\n\n\n/, config)
      assert_valid_ruby config
    end
  end

  test "carries the deprecated options into the appenders, as the engine applies them, and removes them" do
    write("config/application.rb", <<~RUBY)
      module Shop
        class Application < Rails::Application
          config.rails_semantic_logger.ap_options = {multiline: true} # one line per field
          config.rails_semantic_logger.filter = /Healthcheck/
          config.load_defaults 8.1
        end
      end
    RUBY
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        config.rails_semantic_logger.format = :json
        config.rails_semantic_logger.console_logger = false
      end
    RUBY

    run_generator

    assert_file "config/application.rb" do |config|
      refute_includes config, "rails_semantic_logger"
      assert_match(/class Application < Rails::Application\n    config.load_defaults/, config)
    end
    development = "appenders.add(file_name: config.paths[\"log\"].first, " \
                  "formatter: {color: {ap: {multiline: true}}}, " \
                  "filter: /Healthcheck/)"

    assert_file "config/environments/development.rb", Regexp.new(Regexp.escape(development))
    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "    appenders.add(file_name: config.paths[\"log\"].first, formatter: :json, " \
                              "filter: /Healthcheck/)\n"
      assert_includes config, "    # appenders.add_server(io: $stdout, formatter: :color)\n"
      assert_includes config, "    # appenders.add_console(io: $stderr, formatter: :color)\n"
      refute_includes config, "config.rails_semantic_logger.format"
    end
  end

  test "comments out the log file when add_file_appender was false" do
    write("config/environments/test.rb", ENVIRONMENT.sub("config.enable_reloading = true",
                                                         "config.rails_semantic_logger.add_file_appender = false"))

    run_generator

    assert_file "config/environments/test.rb", %r{    # appenders\.add\(file_name: config\.paths\["log"\]\.first}
  end

  test "writes the log file as plain text when colorized logging is off" do
    write("config/environments/development.rb", ENVIRONMENT.sub("config.enable_reloading = true",
                                                                "config.colorize_logging = false"))

    run_generator

    assert_file "config/environments/development.rb",
                /appenders\.add\(file_name: config\.paths\["log"\]\.first, formatter: :default\)/
  end

  test "leaves alone an environment that declares its own appenders" do
    declared = ENVIRONMENT.sub("config.enable_reloading = true",
                               "config.rails_semantic_logger.appenders { |appenders| appenders.add(io: $stdout) }")
    write("config/environments/development.rb", declared)

    run_generator

    assert_file "config/environments/development.rb", declared
    assert_file "config/environments/test.rb", /config\.rails_semantic_logger\.appenders do/
  end

  test "writes no environment's appenders when config/application.rb declares them" do
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1",
                                                   "config.rails_semantic_logger.appenders { |a| a.add(io: $stdout) }"))

    run_generator

    %w[development test production].each do |environment|
      assert_file "config/environments/#{environment}.rb" do |config|
        refute_includes config, "config.rails_semantic_logger.appenders do"
      end
    end
    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "config.logger"
    end
  end

  test "changes nothing when run again" do
    run_generator
    before = %w[development test production].to_h do |environment|
      [environment, read("config/environments/#{environment}.rb")]
    end

    run_generator

    before.each { |environment, config| assert_file "config/environments/#{environment}.rb", config }
  end

  test "leaves a RAILS_LOG_TO_STDOUT block that does more than set the Rails logger, and reports it" do
    container = <<~RUBY
      Rails.application.configure do
        if ENV["RAILS_LOG_TO_STDOUT"].present?
          $stdout.sync = true
          config.rails_semantic_logger.add_file_appender = false
          config.semantic_logger.add_appender(io: $stdout, formatter: :json)
        end
      end
    RUBY
    write("config/environments/production.rb", container)

    output = run_generator

    assert_includes output, "left in place"
    assert_includes output, "config/environments/production.rb: left unchanged: an appenders block would override"
    assert_file "config/environments/production.rb", container
  end

  test "leaves a setting that has a condition of its own, or is inside one" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        config.rails_semantic_logger.format = :json if ENV["JSON"]
        if ENV["SYSLOG"]
          config.logger = Syslog::Logger.new("shop")
        end
      end
    RUBY

    output = run_generator

    # An appenders block would turn off the deprecated option that stays, so the file is left unchanged.
    assert_includes output, "config/environments/production.rb: left unchanged"
    assert_file "config/environments/production.rb" do |config|
      assert_includes config, 'config.rails_semantic_logger.format = :json if ENV["JSON"]'
      assert_includes config, 'config.logger = Syslog::Logger.new("shop")'
      refute_includes config, "config.rails_semantic_logger.appenders"
    end
  end

  test "lists the appenders that the application added, and leaves out the screen when one writes to it" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        config.rails_semantic_logger.add_file_appender = false
        config.semantic_logger.add_appender(io: $stdout, formatter: :json) # for the containers
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "config.semantic_logger.add_appender"
      assert_includes config, "    # appenders.add(file_name: config.paths[\"log\"].first"
      assert_includes config, "    appenders.add(io: $stdout, formatter: :json)\n"
      assert_includes config, "    # appenders.add_server(io: $stdout, formatter: :color)\n"
      assert_valid_ruby config
    end
  end

  test "keeps the appenders that config/application.rb adds when an environment declares its own" do
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1",
                                                   "config.semantic_logger.add_appender(io: $stdout)"))
    declared = "config.rails_semantic_logger.appenders { |a| a.add(io: $stderr) }"
    write("config/environments/test.rb", ENVIRONMENT.sub("config.enable_reloading = true", declared))

    run_generator

    assert_file "config/application.rb", /config\.semantic_logger\.add_appender\(io: \$stdout\)/
  end

  test "adds the appenders to a CRLF file, and after MyApp::Application.configure" do
    write("config/environments/production.rb", <<~RUBY.gsub("\n", "\r\n"))
      Shop::Application.configure do
        config.eager_load = true
        config.logger = ActiveSupport::Logger.new(STDOUT)
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "Shop::Application.configure do\r\n  # Where the logs go."
      refute_includes config, "config.logger"
      refute_match(/[^\r]\n/, config)
      assert_valid_ruby config
    end
  end

  test "changes nothing in a file without a configure block, and reports the options it could not carry" do
    unusual = "config = Rails.application.config\nconfig.rails_semantic_logger.format = :json\n"
    write("config/environments/production.rb", unusual)

    output = run_generator

    assert_file "config/environments/production.rb", unusual
    assert_includes output, "carry these into its appenders: rails_semantic_logger.format"
  end

  test "leaves the rest of the file alone, its heredocs and commented-out settings included" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        BANNER = <<~TEXT
          a


          b
        TEXT

        # Use a different cache store in production.
        # config.cache_store = :mem_cache_store
        config.logger ||= ActiveSupport::Logger.new(STDOUT)
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "    a\n\n\n    b\n"
      assert_includes config,
                      "  # Use a different cache store in production.\n  # config.cache_store = :mem_cache_store\n"
      refute_includes config, "config.logger"
      assert_valid_ruby config
    end
  end

  test "keeps the appenders of config/application.rb when an environment cannot take its block" do
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1",
                                                   "config.semantic_logger.add_appender(appender: :syslog)"))
    unusual = "config = Rails.application.config\nconfig.eager_load = true\n"
    write("config/environments/staging.rb", unusual)

    output = run_generator

    assert_file "config/application.rb", /config\.semantic_logger\.add_appender\(appender: :syslog\)/
    assert_file "config/environments/staging.rb", unusual
    assert_includes output, "config/environments/staging.rb: left unchanged"
    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "\n    appenders.add(appender: :syslog)"
    end
  end

  test "leaves out the screen when config/application.rb keeps an appender that writes to it" do
    added = "config.semantic_logger.add_appender(io: $stdout, formatter: :json)"
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1", added))
    declared = "config.rails_semantic_logger.appenders { |a| a.add(io: $stderr) }"
    write("config/environments/test.rb", ENVIRONMENT.sub("config.enable_reloading = true", declared))

    run_generator

    assert_file "config/application.rb", /add_appender\(io: \$stdout, formatter: :json\)/
    assert_file "config/environments/development.rb", /    # appenders\.add_server\(io: \$stdout, formatter: :color\)\n/
  end

  test "adds the block after Rails' first comment when no blank line follows it" do
    write("config/environments/development.rb",
          "Rails.application.configure do\n  # Settings specified here will take precedence.\n  config.x = 1\nend\n")

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "  # Settings specified here will take precedence.\n\n  # Where the logs go."
      assert_includes config, "  end\n\n  config.x = 1\nend\n"
      assert_valid_ruby config
    end
  end

  test "leaves an added appender that names a local variable, which the block could not see" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        log_path = Rails.root.join("log/app.json")
        config.semantic_logger.add_appender(file_name: log_path, formatter: :json)
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "config.semantic_logger.add_appender(file_name: log_path, formatter: :json)"
      refute_includes config, "appenders.add(file_name: log_path"
    end
  end

  test "leaves a setting inside a condition even when every setting of the file is in one" do
    write("config/environments/staging.rb", <<~RUBY)
      Rails.application.configure do
        if ENV["JSON"]
          config.rails_semantic_logger.format = :json
        end
      end
    RUBY

    run_generator

    assert_file "config/environments/staging.rb" do |config|
      assert_includes config, "    config.rails_semantic_logger.format = :json\n"
      refute_includes config, "config.rails_semantic_logger.appenders"
    end
  end

  test "writes a CRLF file with CRLF line endings only" do
    write("config/environments/production.rb", <<~RUBY.gsub("\n", "\r\n"))
      Rails.application.configure do
        config.semantic_logger.add_appender(
          io: $stdout, formatter: :json
        )
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "\r\r"
      refute_match(/[^\r]\n/, config)
      assert_valid_ruby config
    end
  end

  test "adds the appenders to the application's configure block, not to another library's" do
    write("config/environments/production.rb",
          "Bullet.configure do\n  enable!\nend\n\nRails.application.configure do\n  config.eager_load = true\nend\n")

    run_generator

    assert_file "config/environments/production.rb",
                /Bullet\.configure do\n  enable!\nend\n\nRails\.application\.configure do\n  # Where the logs go/
  end

  test "leaves an added appender that calls a method of the application's own, or reads config" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        config.semantic_logger.add_appender(file_name: log_file("app"), formatter: :json)
        config.semantic_logger.add_appender(io: $stderr, level: config.log_level)
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, 'config.semantic_logger.add_appender(file_name: log_file("app"), formatter: :json)'
      assert_includes config, "config.semantic_logger.add_appender(io: $stderr, level: config.log_level)"
    end
  end

  test "sees a screen appender written over several lines in config/application.rb" do
    added = "config.semantic_logger.add_appender(\n      io: $stdout,\n      formatter: :json\n    )"
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1", added))
    declared = "config.rails_semantic_logger.appenders { |a| a.add(io: $stderr) }"
    write("config/environments/test.rb", ENVIRONMENT.sub("config.enable_reloading = true", declared))

    run_generator

    assert_file "config/environments/development.rb", /    # appenders\.add_server\(io: \$stdout, formatter: :color\)\n/
  end

  test "leaves unchanged an environment whose screen appender has a condition" do
    conditional = 'config.semantic_logger.add_appender(io: $stdout, formatter: :json) if ENV["JSON"]'
    development = ENVIRONMENT.sub("config.enable_reloading = true", conditional)
    write("config/environments/development.rb", development)

    output = run_generator

    # The block's screen lines would print every entry a second time whenever JSON is set.
    assert_includes output, "config/environments/development.rb: left unchanged"
    assert_file "config/environments/development.rb", development
  end

  test "leaves alone the appenders of an environment that loads another one" do
    staging = <<~RUBY
      require_relative "production"

      Rails.application.configure do
        config.semantic_logger.add_appender(appender: :syslog)
        config.rails_semantic_logger.format = :json
      end
    RUBY
    write("config/environments/staging.rb", staging)

    run_generator

    assert_file "config/environments/staging.rb", staging
  end

  test "leaves unchanged an environment that another one loads and keeps its own appender settings" do
    staging = <<~RUBY
      require_relative "production"

      Rails.application.configure do
        config.rails_semantic_logger.format = :json
      end
    RUBY
    write("config/environments/staging.rb", staging)
    production = File.read(File.join(destination_root, "config/environments/production.rb"))

    output = run_generator

    assert_includes output, "config/environments/production.rb: left unchanged: config/environments/staging.rb loads it"
    assert_file "config/environments/production.rb", production
    assert_file "config/environments/staging.rb", staging
  end

  test "leaves unchanged an environment whose screen appender over several lines has a condition" do
    conditional = "config.semantic_logger.add_appender(\n    io: $stdout, formatter: :json\n  ) if ENV[\"JSON\"]"
    development = ENVIRONMENT.sub("config.enable_reloading = true", conditional)
    write("config/environments/development.rb", development)

    output = run_generator

    assert_includes output, "config/environments/development.rb: left unchanged"
    assert_file "config/environments/development.rb", development
  end

  test "moves an appender whose filter is a lambda with a keyword parameter, or the implicit one" do
    added = "config.semantic_logger.add_appender(appender: :syslog, filter: ->(log:) { log.level == :error })\n  " \
            "config.semantic_logger.add_appender(appender: :bugsnag, filter: proc { it.level == :error })"
    write("config/environments/production.rb", ENVIRONMENT.sub("config.enable_reloading = true", added))

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "    appenders.add(appender: :syslog, filter: ->(log:) { log.level == :error })\n"
      assert_includes config, "    appenders.add(appender: :bugsnag, filter: proc { it.level == :error })\n"
      refute_includes config, "config.semantic_logger.add_appender"
    end
  end

  {
    "declares its own appenders" =>
      "config.rails_semantic_logger.appenders { |appenders| appenders.add(io: $stdout, formatter: :json) }",
    "turns colorized logging off" => "config.colorize_logging = false"
  }.each do |what, setting|
    test "leaves unchanged an environment that another one loads and #{what}" do
      staging = %(require_relative "production"\n\nRails.application.configure do\n  #{setting}\nend\n)
      write("config/environments/staging.rb", staging)
      production = File.read(File.join(destination_root, "config/environments/production.rb"))

      run_generator

      assert_file "config/environments/production.rb", production
      assert_file "config/environments/development.rb", /config\.rails_semantic_logger\.appenders do/
    end
  end

  {
    "a local variable beside a block parameter of the same name" =>
      %(log = "log/x.log"\n  config.semantic_logger.add_appender(file_name: log, filter: ->(log) { true })),
    "a local variable named as an implicit block parameter" =>
      "config.semantic_logger.add_appender(appender: :syslog, level: it)",
    "a local variable in a parameter's default value" =>
      "config.semantic_logger.add_appender(appender: :syslog, filter: ->(log, min = threshold) { log.level == min })",
    "a local variable in a keyword parameter's default value" =>
      "config.semantic_logger.add_appender(appender: :syslog, filter: ->(log, level: threshold) { true })",
    "a call chained onto its result" =>
      "config.semantic_logger.add_appender(appender: :syslog).name = Name.new(1)"
  }.each do |what, added|
    test "keeps in place an appender that reads #{what}" do
      write("config/environments/production.rb", ENVIRONMENT.sub("config.enable_reloading = true", added))

      run_generator

      assert_file "config/environments/production.rb" do |config|
        assert_includes config, added.lines.last
        assert_includes config, "config.rails_semantic_logger.appenders do"
      end
    end
  end

  test "moves an appender whose filter has a block-local variable" do
    added = "config.semantic_logger.add_appender(appender: :syslog, filter: proc { |log; level| level = log.level })"
    write("config/environments/production.rb", ENVIRONMENT.sub("config.enable_reloading = true", added))

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "    appenders.add(appender: :syslog, filter: proc { |log; level| level = log.level })\n"
      refute_includes config, "config.semantic_logger.add_appender"
    end
  end

  test "leaves unchanged an environment that turns colors off only sometimes" do
    development = ENVIRONMENT.sub("config.enable_reloading = true", 'config.colorize_logging = false if ENV["CI"]')
    write("config/environments/development.rb", development)

    output = run_generator

    assert_includes output, "config/environments/development.rb: left unchanged"
    assert_file "config/environments/development.rb", development
    assert_file "config/environments/test.rb", /formatter: \{color: \{ap: \{multiline: false\}\}\}/
  end

  {
    "assigned"                   => 'config.paths["log"] = "/var/log/shop.log"',
    "without config"             => 'paths["log"] = "/var/log/shop.log"',
    "through Rails.application"  => 'Rails.application.config.paths["log"] = "/var/log/shop.log"',
    "unshifted"                  => 'config.paths["log"].unshift("/var/log/shop.log")',
    "added"                      => 'config.paths.add "log", with: "/var/log/shop.log"',
    "added over several lines"   => %(config.paths.add(\n    "log", with: "/var/log/shop.log"\n  )),
    "added on the next line"     => %(config.paths\n    .add("log", with: "/var/log/shop.log")),
    "globbed"                    => 'config.paths["log"].glob = "*.log"',
    "tapped"                     => 'config.paths["log"].tap { |path| path.unshift("/var/log/shop.log") }',
    "set inside a tap of paths"  => 'config.paths.tap { |paths| paths["log"] = "/var/log/shop.log" }',
    "set inside a then of paths" => 'config.paths.then { |all| all["log"] = "/var/log/shop.log" }',
    "set through a variable"     => %(all = config.paths\n  all["log"] = "/var/log/shop.log"),
    "added through safe nav"     => 'config.paths&.add("log", with: "/var/log/shop.log")'
  }.each do |how, setting|
    test "leaves unchanged an environment that sets where the log file goes: #{how}" do
      production = ENVIRONMENT.sub("config.enable_reloading = true", setting)
      write("config/environments/production.rb", production)

      output = run_generator

      assert_includes output, "production.rb: left unchanged: it sets config.paths[\"log\"]"
      assert_file "config/environments/production.rb", production
    end
  end

  {
    "a read"                     => 'config.x.log_file = config.paths["log"].first',
    "a chained read"             => 'config.x.log_dir = File.dirname(config.paths["log"].expanded.first)',
    "another path added"         => 'config.paths.add "app/services", eager_load: true',
    "a comment that mentions it" => 'config.log_level = :info # the log file is config.paths["log"]',
    "a block comment"            => %(config.x.a = 1\n=begin\nconfig.paths["log"] = "/var/log/shop.log"\n=end),
    "another named path"         => 'config.paths["config/routes"] << "config/admin_routes.rb"',
    "another read"               => 'config.x.log_dirs = config.paths["log"].existent_directories'
  }.each do |what, line|
    test "converts an environment whose file holds #{what} of the log path" do
      write("config/environments/production.rb", ENVIRONMENT.sub("config.enable_reloading = true", line))

      run_generator

      assert_file "config/environments/production.rb", /config\.rails_semantic_logger\.appenders do/
    end
  end

  test "follows the loads to an environment that sets where the log file goes" do
    write("config/environments/staging.rb", %(require_relative "production"\n))
    qa = %(require_relative "staging"\n\nRails.application.configure do\n  ) +
         %(config.paths["log"] = "/var/log/qa.log"\nend\n)
    write("config/environments/qa.rb", qa)
    production = File.read(File.join(destination_root, "config/environments/production.rb"))

    output = run_generator

    assert_includes output, "production.rb: left unchanged: config/environments/qa.rb loads it " \
                            "(through config/environments/staging.rb), and sets config.paths"
    assert_file "config/environments/production.rb", production
  end

  test "names the log path as the reason when the environment that loads this one sets it" do
    staging = %(require_relative "production"\n\nRails.application.configure do\n  ) +
              %(config.paths["log"] = "/var/log/staging.log"\nend\n)
    write("config/environments/staging.rb", staging)

    output = run_generator

    assert_includes output, "production.rb: left unchanged: config/environments/staging.rb loads it, " \
                            "and sets config.paths[\"log\"]"
  end

  test "reads the log file that config/application.rb sets, in each environment's block" do
    log_path = 'config.paths["log"] = "/var/log/shop.log"'
    write("config/application.rb", APPLICATION.sub("config.load_defaults 8.1", log_path))

    run_generator

    assert_file "config/application.rb", %r{config\.paths\["log"\] = "/var/log/shop\.log"}
    assert_file "config/environments/production.rb", /appenders\.add\(file_name: config\.paths\["log"\]\.first, /
  end

  test "leaves unchanged an environment that turns off both the log file and the screen" do
    off = "config.rails_semantic_logger.add_file_appender = false\n  " \
          "config.rails_semantic_logger.console_logger = false"
    production = ENVIRONMENT.sub("config.enable_reloading = true", off)
    write("config/environments/production.rb", production)

    output = run_generator

    assert_includes output, "production.rb: left unchanged: its appenders block would declare no appender"
    assert_file "config/environments/production.rb", production
  end

  test "converts add_file_appender and console_logger only when set to true or false" do
    computed   = 'config.rails_semantic_logger.add_file_appender = ENV["LOG_TO_FILE"].present?'
    production = ENVIRONMENT.sub("config.enable_reloading = true", computed)
    write("config/environments/production.rb", production)

    output = run_generator

    assert_includes output, "left in place, move it into the appenders: #{computed}"
    assert_file "config/environments/production.rb", production
  end

  test "leaves an option whose value names a local variable" do
    local      = "formatter = :json\n  config.rails_semantic_logger.format = formatter"
    production = ENVIRONMENT.sub("config.enable_reloading = true", local)
    write("config/environments/production.rb", production)

    run_generator

    assert_file "config/environments/production.rb", production
  end

  test "moves an appender whose filter is a lambda with a parameter" do
    added = "config.semantic_logger.add_appender(appender: :syslog, filter: ->(log) { log.level == :error })"
    write("config/environments/production.rb", ENVIRONMENT.sub("config.enable_reloading = true", added))

    run_generator

    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "    appenders.add(appender: :syslog, filter: ->(log) { log.level == :error })\n"
      refute_includes config, "config.semantic_logger.add_appender"
      assert_valid_ruby config
    end
  end

  test "keeps the options of config/application.rb when an environment cannot take its block" do
    application = APPLICATION.sub("config.load_defaults 8.1", "config.rails_semantic_logger.format = :json")
    write("config/application.rb", application)
    write("config/environments/staging.rb", "config = Rails.application.config\nconfig.eager_load = true\n")

    run_generator

    assert_file "config/application.rb", application
    assert_file "config/environments/production.rb" do |config|
      refute_includes config, "config.rails_semantic_logger.appenders"
    end
  end

  test "finds the top level of the settings in the application's configure block, not another library's" do
    write("config/environments/production.rb", <<~RUBY)
      if defined?(Bullet)
        Bullet.configure do
          enable!
        end
      end

      Rails.application.configure do
        if ENV["SYSLOG"]
          config.logger = Syslog::Logger.new("shop")
        end
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb", /    config\.logger = Syslog::Logger\.new\("shop"\)/
  end

  test "writes no appenders block into an environment that loads another environment's settings" do
    inherited = "require_relative \"production\"\n\nRails.application.configure do\n  config.x = 1\nend\n"
    write("config/environments/staging.rb", inherited)

    output = run_generator

    assert_file "config/environments/staging.rb", inherited
    assert_includes output, "staging.rb: it loads another environment's settings"
    assert_file "config/environments/production.rb", /config\.rails_semantic_logger\.appenders do/
  end

  test "moves an added appender whose filter is a lambda" do
    write("config/environments/production.rb", <<~RUBY)
      Rails.application.configure do
        config.semantic_logger.add_appender(io: $stderr, filter: lambda { true })
      end
    RUBY

    run_generator

    assert_file "config/environments/production.rb", /    appenders\.add\(io: \$stderr, filter: lambda \{ true \}\)\n/
  end

  test "adds the appenders inside `configure do |config|`" do
    write("config/environments/production.rb", "Rails.application.configure do |config|\n  config.x = 1\nend\n")

    run_generator

    assert_file "config/environments/production.rb", /configure do \|config\|\n  # Where the logs go\./
  end

  test "changes no settings file when destroyed" do
    run_generator
    configured = %w[application.rb environments/production.rb].to_h { |path| [path, read("config/#{path}")] }

    run_generator [], behavior: :revoke

    configured.each { |path, text| assert_file "config/#{path}", text }
  end

  private

  def assert_valid_ruby(source)
    refute_nil Ripper.sexp(source), "not valid Ruby:\n#{source}"
  end

  def write(path, content)
    full = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def read(path) = File.read(File.join(destination_root, path))
end
