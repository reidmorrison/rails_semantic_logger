require_relative "../test_helper"
require "ripper"
require "generators/rails_semantic_logger/observability/observability_generator"

class ObservabilityGeneratorTest < Rails::Generators::TestCase
  tests RailsSemanticLogger::Generators::ObservabilityGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  DEVELOPMENT = <<~RUBY.freeze
    Rails.application.configure do
      config.enable_reloading = true
    end
  RUBY

  setup do
    prepare_destination
    write("config/environments/development.rb", DEVELOPMENT)
    write("config/environments/production.rb", DEVELOPMENT)
  end

  test "writes the stack and the traffic task" do
    run_generator

    assert_file "compose.observability.yml", /^services:$/
    assert_file "observability/otel-collector.yaml"
    assert_file "observability/grafana/provisioning/datasources/clickhouse.yaml"
    assert_file "observability/grafana/provisioning/dashboards/semantic_logger.yaml"
    assert_file "lib/tasks/semantic_logger.rake", /task traffic: :environment/
  end

  test "pins every image of the stack" do
    run_generator

    assert_file "compose.observability.yml" do |compose|
      images = compose.scan(/^\s+image: (\S+)$/).flatten

      assert_equal 3, images.size
      images.each { |image| assert_match(/:\d+(\.\d+)+\z/, image) }
    end
  end

  test "queries every dashboard panel through the provisioned data source" do
    run_generator

    datasource     = File.read(destination_path("observability/grafana/provisioning/datasources/clickhouse.yaml"))
    datasource_uid = datasource[/uid: (\S+)/, 1]
    dashboards     = Dir[destination_path("observability/grafana/dashboards/*.json")]

    assert_equal %w[jobs.json logs.json rails.json], dashboards.map { |path| File.basename(path) }.sort
    dashboards.each do |path|
      panels = JSON.parse(File.read(path)).fetch("panels").reject { |panel| panel["type"] == "row" }

      refute_empty panels, path
      panels.each do |panel|
        panel.fetch("targets").each do |target|
          assert_equal datasource_uid, target.dig("datasource", "uid"), "#{path}: #{panel['title']}"
          assert_includes target.fetch("rawSql"), "${service:sqlstring}", "#{path}: #{panel['title']}"
        end
      end
    end
  end

  test "lists every environment's appenders, then adds the OTLP ones to development" do
    run_generator

    assert_file "config/environments/development.rb" do |config|
      block = config[/  config\.rails_semantic_logger\.appenders do \|appenders\|\n.*?\n  end\n/m].to_s

      assert_includes block, "    appenders.add(file_name: "
      assert_includes block, "    appenders.add(appender: :otlp)\n    appenders.add(metric: :otlp, interval: 10)\n"
      refute_includes config, "#   bin/rails generate rails_semantic_logger:observability"
      application = "  end\n\n  # The service.name of the logs and metrics sent to the observability stack.\n  " \
                    "config.semantic_logger.application = \"dummy\"\n"

      assert_includes config, application
      refute_nil Ripper.sexp(config), "development.rb is not valid Ruby:\n#{config}"
    end
    assert_file "config/environments/production.rb" do |config|
      assert_includes config, "appenders.add(file_name: "
      refute_includes config, "\n    appenders.add(appender: :otlp)"
    end
  end

  test "adds the OTLP appenders inside the development appenders the application declared" do
    write("config/environments/development.rb", <<~RUBY)
      Rails.application.configure do
        config.rails_semantic_logger.appenders do |list|
          list.add(io: $stdout, formatter: :json)
        end
      end
    RUBY

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_match(/list\.add\(io: \$stdout, formatter: :json\)\n\n(?:    #.*\n)+/, config)
      assert_includes config, "    list.add(appender: :otlp)\n    list.add(metric: :otlp, interval: 10)\n  end\n"
      refute_includes config, "log/development.log"
      refute_nil Ripper.sexp(config), config
    end
  end

  test "adds a development block of only the OTLP appenders when config/application.rb declares the appenders" do
    write("config/application.rb", <<~RUBY)
      config.rails_semantic_logger.appenders do |appenders|
        appenders.add(io: $stdout, formatter: :json)
      end
    RUBY

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "    appenders.add(appender: :otlp)\n"
      refute_includes config, "log/development.log"
      refute_nil Ripper.sexp(config), config
    end
  end

  test "says where to add the OTLP appenders when it finds no appenders block, and changes nothing" do
    unusual = "config = Rails.application.config\nconfig.enable_reloading = true\n"
    write("config/environments/development.rb", unusual)

    output = run_generator

    assert_file "config/environments/development.rb", unusual
    assert_includes output, "found no appenders block"
    assert_includes output, "appenders.add(appender: :otlp)"
  end

  test "adds the OTLP appenders to a CRLF development file" do
    write("config/environments/development.rb", DEVELOPMENT.gsub("\n", "\r\n"))

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "    appenders.add(appender: :otlp)\r\n"
      refute_includes config, "\r\r"
      refute_match(/[^\r]\n/, config)
    end
  end

  test "adds a block of only the OTLP appenders when development declares its appenders with braces" do
    declared = "Rails.application.configure do\n  " \
               "config.rails_semantic_logger.appenders { |a| a.add(io: $stdout) }\nend\n"
    write("config/environments/development.rb", declared)

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "{ |a| a.add(io: $stdout) }"
      assert_includes config, "    appenders.add(appender: :otlp)\n"
      refute_nil Ripper.sexp(config), config
    end
  end

  test "adds a block of only the OTLP appenders to a CRLF file after MyApp::Application.configure" do
    declared = "Dummy::Application.configure do\n  " \
               "config.rails_semantic_logger.appenders { |a| a.add(io: $stdout) }\nend\n"
    write("config/environments/development.rb", declared.gsub("\n", "\r\n"))

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config,
                      "Dummy::Application.configure do\r\n  config.rails_semantic_logger.appenders do |appenders|\r\n"
      assert_includes config, "    appenders.add(appender: :otlp)\r\n"
      refute_match(/[^\r]\n/, config)
    end
  end

  test "adds only the OTLP log appender when development already sends its metrics to OTLP" do
    metrics = "Rails.application.configure do\n  " \
              "config.rails_semantic_logger.appenders { |a| a.add(metric: :otlp) }\nend\n"
    write("config/environments/development.rb", metrics)

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "appenders.add(appender: :otlp)\n"
      assert_equal 1, config.scan("metric: :otlp").size
    end
  end

  test "adds no OTLP appender of a kind that development sends only sometimes, and says so" do
    sometimes = <<~RUBY
      Rails.application.configure do
        config.rails_semantic_logger.appenders do |appenders|
          appenders.add(file_name: "log/development.log")
          appenders.add(appender: :otlp) if ENV["OTLP"]
          appenders.add_server(metric: :otlp)
        end
      end
    RUBY
    write("config/environments/development.rb", sometimes)

    output = run_generator

    assert_includes output, "sends its logs and metrics to OTLP only sometimes"
    assert_file "config/environments/development.rb", sometimes
  end

  test "counts a one-line block's add_server or conditional OTLP appender as sending only sometimes" do
    one_line = "Rails.application.configure do\n  " \
               "config.rails_semantic_logger.appenders { |a| a.add_server(metric: :otlp) }\nend\n"
    write("config/environments/development.rb", one_line)

    output = run_generator

    assert_includes output, "sends its metrics to OTLP only sometimes"
    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "appenders.add(appender: :otlp)\n"
      assert_equal 1, config.scan("metric: :otlp").size
      assert_includes config, "# Send the logs to the local observability stack"
    end
  end

  test "adds nothing to an appenders block with a condition on its end" do
    conditional = <<~RUBY
      Rails.application.configure do
        config.rails_semantic_logger.appenders do |appenders|
          appenders.add(io: $stdout, formatter: :json)
        end if ENV["JSON"]
      end
    RUBY
    write("config/environments/development.rb", conditional)

    run_generator

    assert_file "config/environments/development.rb", conditional
  end

  test "adds no OTLP appenders a second time, beside a conditional line of the block" do
    run_generator
    conditional = "    appenders.add(io: $stdout) if ENV[\"STDOUT\"]\n"
    first       = File.read(destination_path("config/environments/development.rb")).
                  sub("    appenders.add_server(", "#{conditional}    appenders.add_server(")
    write("config/environments/development.rb", first)

    run_generator

    assert_file "config/environments/development.rb", first
  end

  test "keeps development's settings when destroyed" do
    declared = "Rails.application.configure do\n  " \
               "config.rails_semantic_logger.appenders { |a| a.add(io: $stdout) }\nend\n"
    write("config/environments/development.rb", declared)

    run_generator [], behavior: :revoke

    assert_file "config/environments/development.rb", declared
  end

  test "leaves development alone when it already sends to OTLP" do
    run_generator
    configured = File.read(destination_path("config/environments/development.rb"))

    run_generator

    assert_file "config/environments/development.rb", configured
  end

  test "changes no file with --pretend, nor lets the install generator change one" do
    run_generator %w[--pretend]

    assert_file "config/environments/development.rb", DEVELOPMENT
    assert_file "config/environments/production.rb", DEVELOPMENT
    assert_no_file "compose.observability.yml"
  end

  test "drops the hint to run it from the block that rails_semantic_logger:install wrote before" do
    Rails::Generators.invoke("rails_semantic_logger:install", [], destination_root: destination_root, behavior: :invoke,
                                                                  quiet: true)

    assert_file "config/environments/development.rb", %r{bin/rails generate rails_semantic_logger:observability}

    run_generator

    assert_file "config/environments/development.rb" do |config|
      refute_includes config, "#   bin/rails generate rails_semantic_logger:observability"
      assert_includes config, "    appenders.add(appender: :otlp)\n"
      refute_nil Ripper.sexp(config)
    end
  end

  test "adds nothing to an appenders block inside a condition, and does not say the logs go to the stack" do
    conditional = <<~RUBY
      Rails.application.configure do
        config.enable_reloading = true
        if ENV["JSON"]
          config.rails_semantic_logger.appenders do |appenders|
            appenders.add(io: $stdout, formatter: :json)
          end
        end
      end
    RUBY
    write("config/environments/development.rb", conditional)

    output = run_generator

    assert_file "config/environments/development.rb" do |config|
      refute_includes config, "appender: :otlp"
    end
    assert_includes output, "Development does not send to the stack yet"
    refute_includes output, "now goes to the stack"
  end

  test "adds no OTLP appenders when config/application.rb already sends to OTLP" do
    write("config/application.rb", <<~RUBY)
      module Shop
        class Application < Rails::Application
          config.rails_semantic_logger.appenders do |appenders|
            appenders.add(appender: :otlp)
            appenders.add(metric: :otlp)
          end
        end
      end
    RUBY

    run_generator

    assert_file "config/environments/development.rb", DEVELOPMENT
  end

  test "keeps the application name that config/application.rb sets" do
    write("config/application.rb", <<~RUBY)
      module Shop
        class Application < Rails::Application
          config.semantic_logger.application = "storefront"
        end
      end
    RUBY

    run_generator

    assert_file "config/environments/development.rb" do |config|
      refute_includes config, "config.semantic_logger.application ="
      assert_includes config, "appenders.add(appender: :otlp)"
    end
  end

  test "does not take OTLP appenders that config/application.rb adds under a condition as sending" do
    write("config/application.rb", <<~RUBY)
      module Shop
        class Application < Rails::Application
          if Rails.env.production?
            config.rails_semantic_logger.appenders do |appenders|
              appenders.add(appender: :otlp)
            end
          end
        end
      end
    RUBY

    output = run_generator

    refute_includes output, "already sends to OTLP"
    refute_includes output, "now goes to the stack"
  end

  test "prints no next steps when destroyed" do
    run_generator
    output = run_generator [], behavior: :revoke

    refute_includes output, "Development does not send"
    refute_includes output, "now goes to the stack"
  end

  test "says, when pretending, that the OTLP appenders go in the block that the install step writes" do
    output = run_generator %w[--pretend]

    refute_includes output, "found no appenders block"
    assert_includes output, "rails_semantic_logger:install writes"
  end

  test "keeps the application name that development already sets" do
    write("config/environments/development.rb",
          DEVELOPMENT.sub("config.enable_reloading = true", "config.enable_reloading = true\n  " \
                                                            'config.semantic_logger.application = "storefront"'))

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, 'config.semantic_logger.application = "storefront"'
      assert_equal 1, config.scan("config.semantic_logger.application =").size
    end
  end

  private

  def write(path, content)
    full = destination_path(path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def destination_path(path) = File.join(destination_root, path)
end
