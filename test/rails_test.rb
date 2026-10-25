require_relative "test_helper"

class RailsTest < Minitest::Test
  describe "Rails" do
    describe ".logger" do
      it "replaces the Rails logger" do
        assert_kind_of SemanticLogger::Logger, Rails.logger
      end

      it "uses the colorized formatter" do
        assert_kind_of SemanticLogger::Formatters::Color, SemanticLogger.appenders.first.formatter
      end

      it "is compatible with Rails logger" do
        assert_nil Rails.logger.formatter
        Rails.logger.formatter = "blah"

        assert_equal "blah", Rails.logger.formatter
      end
    end

    # Rails' own :initialize_logger wraps every Rails.logger in an
    # ActiveSupport::BroadcastLogger (railties application/bootstrap.rb). BroadcastLogger
    # has no #tagged of its own, so the call falls through to its #method_missing, which
    # forwards to each broadcast target in turn and therefore runs the supplied block once
    # per target. See https://github.com/rails/rails/issues/49745: the block runs N times,
    # which inside a request makes the Rack logger return N responses and raises a
    # TypeError in ActionDispatch::RequestId.
    #
    # This gem is immune by construction rather than by a workaround: the engine deletes
    # :initialize_logger and assigns a plain SemanticLogger::Logger, which multiplexes to
    # its appenders from a single object, so a tagged block is always yielded once. These
    # tests exist so that a change in either half of that arrangement fails here instead of
    # in an application.
    describe "broadcast logging" do
      it "is not wrapped in a BroadcastLogger" do
        refute_kind_of ActiveSupport::BroadcastLogger, Rails.logger
      end

      it "assigns the same logger to config.logger" do
        assert_same Rails.logger, Rails.application.config.logger
      end

      # Rails calls Rails.logger.broadcast_to from `rails server` (log_to_stdout) and from
      # the ActiveRecord console hook, both guarded by this predicate. SemanticLogger has
      # no #broadcast_to, so the override in extensions/active_support/logger.rb reports
      # that the console is already covered and leaves both branches unused.
      it "reports that the logger already outputs to the console" do
        assert ActiveSupport::Logger.logger_outputs_to?(Rails.logger, $stdout, $stderr),
               "Rails would otherwise call Rails.logger.broadcast_to, which SemanticLogger does not implement"
      end

      describe "with several appenders" do
        before do
          @original_appenders = SemanticLogger.appenders.to_a
        end

        after do
          (SemanticLogger.appenders.to_a - @original_appenders).each do |appender|
            SemanticLogger.remove_appender(appender)
          end
        end

        it "yields a tagged block once and tags every appender" do
          first  = StringIO.new
          second = StringIO.new
          SemanticLogger.add_appender(io: first, formatter: :default)
          SemanticLogger.add_appender(io: second, formatter: :default)

          runs = 0
          Rails.logger.tagged("TEST") do
            runs += 1
            Rails.logger.error("Doing something")
          end
          SemanticLogger.flush

          assert_equal 1, runs, "the tagged block must run once, not once per appender"
          [first, second].each do |io|
            assert_includes io.string, "TEST"
            assert_equal 1, io.string.scan("Doing something").size
          end
        end
      end
    end
  end
end
