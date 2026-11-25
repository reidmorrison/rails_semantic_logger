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

  test "adds the OTLP appenders to development, with the default appenders" do
    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, 'config.semantic_logger.application = "dummy"'
      assert_includes config, 'appenders.add(file_name: "log/development.log", formatter: :color)'
      assert_includes config, "appenders.add_server"
      assert_includes config, "appenders.add_console"
      assert_includes config, "appenders.add(appender: :otlp)"
      assert_includes config, "appenders.add(metric: :otlp, interval: 10)"
      refute_nil Ripper.sexp(config), "development.rb is not valid Ruby:\n#{config}"
    end
  end

  test "adds only the OTLP appenders when the application declares its own" do
    write("config/application.rb", <<~RUBY)
      config.rails_semantic_logger.appenders do |appenders|
        appenders.add(io: $stdout, formatter: :json)
      end
    RUBY

    run_generator

    assert_file "config/environments/development.rb" do |config|
      assert_includes config, "appenders.add(appender: :otlp)"
      refute_includes config, "appenders.add_server"
      refute_includes config, "log/development.log"
    end
  end

  test "leaves development alone when it already sends to OTLP" do
    run_generator
    configured = File.read(destination_path("config/environments/development.rb"))

    run_generator

    assert_file "config/environments/development.rb", configured
  end

  test "changes no other environment" do
    write("config/environments/production.rb", DEVELOPMENT)

    run_generator

    assert_file "config/environments/production.rb", DEVELOPMENT
  end

  private

  def write(path, content)
    full = destination_path(path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def destination_path(path) = File.join(destination_root, path)
end
