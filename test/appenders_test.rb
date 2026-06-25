require_relative "test_helper"

class AppendersTest < Minitest::Test
  # Run the block while capturing any deprecation warnings emitted by the gem's deprecator.
  def self.capture_deprecations
    collected = []
    original  = RailsSemanticLogger.deprecator.behavior
    RailsSemanticLogger.deprecator.behavior = ->(message, *) { collected << message }
    yield
    collected
  ensure
    RailsSemanticLogger.deprecator.behavior = original
  end

  describe RailsSemanticLogger::Appenders do
    let(:appenders) { RailsSemanticLogger::Appenders.new }

    it "starts empty" do
      refute_predicate appenders, :any?
    end

    it "accumulates declarations and reports any?" do
      appenders.add(file_name: "log/test.log", formatter: :json)

      assert_predicate appenders, :any?
    end

    it "yields each declaration as [args, block]" do
      block = ->(log) { "#{log.message}!" }
      appenders.add(io: $stdout, formatter: :color)
      appenders.add(file_name: "log/test.log", &block)

      collected = appenders.to_a

      assert_equal({io: $stdout, formatter: :color}, collected[0][0])
      assert_nil collected[0][1]
      assert_equal({file_name: "log/test.log"}, collected[1][0])
      assert_same block, collected[1][1]
    end

    it "is chainable" do
      result = appenders.add(io: $stdout).add(file_name: "log/test.log")

      assert_same appenders, result
      assert_equal 2, appenders.to_a.size
    end

    describe "#add_server" do
      it "keeps context declarations out of the init-time appenders" do
        appenders.add_server

        assert_empty appenders.to_a
        assert_predicate appenders, :any?
      end

      it "defaults to $stdout with the :color formatter" do
        appenders.add_server

        args, block = appenders.server.first

        assert_equal({formatter: :color, io: $stdout}, args)
        assert_nil block
      end

      it "does not add the default io when another destination is given" do
        appenders.add_server(file_name: "log/server.log", formatter: :json)

        assert_equal({formatter: :json, file_name: "log/server.log"}, appenders.server.first[0])
      end

      it "allows overriding the io, formatter, and extra options" do
        appenders.add_server(io: $stderr, formatter: :json, level: :warn)

        assert_equal({formatter: :json, io: $stderr, level: :warn}, appenders.server.first[0])
      end

      it "is chainable and accumulates" do
        result = appenders.add_server.add_server(file_name: "log/server.log")

        assert_same appenders, result
        assert_equal 2, appenders.server.size
      end
    end

    describe "#add_console" do
      it "keeps context declarations out of the init-time appenders" do
        appenders.add_console

        assert_empty appenders.to_a
        assert_predicate appenders, :any?
      end

      it "defaults to $stderr with the :color formatter" do
        appenders.add_console

        args, block = appenders.console.first

        assert_equal({formatter: :color, io: $stderr}, args)
        assert_nil block
      end

      it "does not add the default io when another destination is given" do
        appenders.add_console(file_name: "log/console.log", formatter: :json)

        assert_equal({formatter: :json, file_name: "log/console.log"}, appenders.console.first[0])
      end

      it "is tracked separately from #add_server" do
        appenders.add_server
        appenders.add_console

        assert_equal({formatter: :color, io: $stdout}, appenders.server.first[0])
        assert_equal({formatter: :color, io: $stderr}, appenders.console.first[0])
      end
    end
  end

  describe RailsSemanticLogger::Options do
    let(:options) { RailsSemanticLogger::Options.new }

    describe "#appenders" do
      it "is empty by default" do
        refute_predicate options, :appenders?
      end

      it "collects appenders declared in the block" do
        options.appenders do |appenders|
          appenders.add(file_name: "log/test.log", formatter: :json)
          appenders.add(io: $stdout, formatter: :color)
        end

        assert_predicate options, :appenders?
        assert_equal 2, options.appenders.to_a.size
      end

      it "returns the same collection across calls" do
        first = options.appenders

        assert_same first, options.appenders
      end
    end

    describe "deprecated options" do
      it "warns when assigning format but still sets it" do
        messages = AppendersTest.capture_deprecations { options.format = :json }

        assert_match(/format/, messages.first)
        assert_equal :json, options.format
      end

      it "warns when assigning ap_options but still sets it" do
        messages = AppendersTest.capture_deprecations { options.ap_options = {multiline: true} }

        assert_match(/ap_options/, messages.first)
        assert_equal({multiline: true}, options.ap_options)
      end

      it "warns when assigning filter but still sets it" do
        filter   = /MyClass/
        messages = AppendersTest.capture_deprecations { options.filter = filter }

        assert_match(/filter/, messages.first)
        assert_same filter, options.filter
      end

      it "warns when assigning console_logger but still sets it" do
        messages = AppendersTest.capture_deprecations { options.console_logger = false }

        assert_match(/console_logger/, messages.first)
        refute options.console_logger
      end
    end
  end

  describe ".add_console_appender" do
    before do
      @original_appenders = SemanticLogger.appenders.to_a
    end

    after do
      (SemanticLogger.appenders.to_a - @original_appenders).each { |appender| SemanticLogger.remove_appender(appender) }
    end

    it "adds a console appender when none exists" do
      refute_predicate SemanticLogger.appenders, :console_output?, "expected no console appender before the test"

      RailsSemanticLogger.add_console_appender(io: $stderr)

      assert_predicate SemanticLogger.appenders, :console_output?
    end

    it "does not add a second console appender" do
      RailsSemanticLogger.add_console_appender(io: $stderr)
      count = SemanticLogger.appenders.size

      RailsSemanticLogger.add_console_appender(io: $stderr)

      assert_equal count, SemanticLogger.appenders.size
    end

    it "adds no console appender when the app owns appender config but declared no add_server" do
      options = Rails.application.config.rails_semantic_logger
      options.stub(:appenders?, true) do
        RailsSemanticLogger.add_console_appender(io: $stderr)
      end

      refute_predicate SemanticLogger.appenders, :console_output?
    end

    it "creates the declared add_server appenders when the app owns appender config" do
      declared = RailsSemanticLogger::Appenders.new
      declared.add_server(io: $stderr)

      options = Rails.application.config.rails_semantic_logger
      options.stub(:appenders?, true) do
        options.stub(:appenders, declared) do
          RailsSemanticLogger.add_console_appender(io: $stdout)
        end
      end

      assert_predicate SemanticLogger.appenders, :console_output?
    end

    it "creates the declared add_console appenders when declared: :console" do
      declared = RailsSemanticLogger::Appenders.new
      declared.add_console(io: $stderr)

      options = Rails.application.config.rails_semantic_logger
      options.stub(:appenders?, true) do
        options.stub(:appenders, declared) do
          RailsSemanticLogger.add_console_appender(io: $stderr, declared: :console)
        end
      end

      assert_predicate SemanticLogger.appenders, :console_output?
    end

    it "does not create add_server appenders when asked for the console list" do
      declared = RailsSemanticLogger::Appenders.new
      declared.add_server(io: $stderr)

      options = Rails.application.config.rails_semantic_logger
      options.stub(:appenders?, true) do
        options.stub(:appenders, declared) do
          RailsSemanticLogger.add_console_appender(io: $stderr, declared: :console)
        end
      end

      refute_predicate SemanticLogger.appenders, :console_output?
    end
  end

  describe ".add_server_appenders" do
    before do
      @original_appenders = SemanticLogger.appenders.to_a
    end

    after do
      (SemanticLogger.appenders.to_a - @original_appenders).each { |appender| SemanticLogger.remove_appender(appender) }
    end

    it "creates the declared add_server appenders" do
      declared = RailsSemanticLogger::Appenders.new
      declared.add_server(io: $stderr)

      options = Rails.application.config.rails_semantic_logger
      options.stub(:appenders?, true) do
        options.stub(:appenders, declared) do
          RailsSemanticLogger.add_server_appenders
        end
      end

      assert_predicate SemanticLogger.appenders, :console_output?
    end

    it "is idempotent when a console appender already exists" do
      RailsSemanticLogger.add_server_appenders
      count = SemanticLogger.appenders.size

      RailsSemanticLogger.add_server_appenders

      assert_equal count, SemanticLogger.appenders.size
    end
  end

  describe ".add_appenders" do
    it "creates each declared appender and uses the first file appender as the internal logger" do
      io                = StringIO.new
      dir               = Dir.mktmpdir
      path              = File.join(dir, "custom.log")
      original_internal = SemanticLogger::Processor.logger
      original_count    = SemanticLogger.appenders.size

      appenders = RailsSemanticLogger::Appenders.new
      appenders.add(io: io, formatter: :json)
      appenders.add(file_name: path, formatter: :default)

      RailsSemanticLogger.add_appenders(appenders)

      added = SemanticLogger.appenders.to_a.last(2)

      assert_equal 2, SemanticLogger.appenders.size - original_count
      assert_kind_of SemanticLogger::Appender::File, SemanticLogger::Processor.logger
      assert_equal path, SemanticLogger::Processor.logger.file_name
    ensure
      added&.each { |appender| SemanticLogger.remove_appender(appender) }
      SemanticLogger::Processor.logger = original_internal
      FileUtils.remove_entry(dir) if dir
    end
  end
end
