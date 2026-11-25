require_relative "../test_helper"

module Metrics
  class SubscriberTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::Subscriber do
      let(:subscriber_class) do
        Class.new(RailsSemanticLogger::Metrics::Subscriber) do
          def self.name = "BrokenMetrics"
          const_set(:LOGGER_NAME, "BrokenMetrics")

          def broken(_event)
            raise ArgumentError, "boom"
          end
        end
      end

      it "refuses to attach a subscriber that names no logger" do
        unnamed = Class.new(RailsSemanticLogger::Metrics::Subscriber) { def self.name = "UnnamedMetrics" }

        error = assert_raises(NameError) { unnamed.attach_to(:unnamed_metrics_test) }
        assert_match(/LOGGER_NAME/, error.message)
      end

      it "does not read the event while no metric appender collects the metrics" do
        subscriber = subscriber_class.new
        event      = ActiveSupport::Notifications::Event.new("broken.test", Time.now, Time.now, "1", {})
        internal   = SemanticLogger::Test::CaptureLogEvents.new

        subscriber_class.logger.stub(:collecting_metrics?, false) do
          SemanticLogger::Processor.stub(:logger, internal) { subscriber.call(event) }
        end

        assert_empty internal.events
      end

      it "is silenced while no metric appender collects the metrics" do
        subscriber = subscriber_class.new

        subscriber_class.logger.stub(:collecting_metrics?, false) { assert subscriber.silenced?("broken.test") }
        subscriber_class.logger.stub(:collecting_metrics?, true) { refute subscriber.silenced?("broken.test") }
      end

      it "listens when it cannot tell whether the metrics are collected" do
        subscriber = subscriber_class.new
        failing    = -> { raise ArgumentError, "boom" }

        subscriber_class.logger.stub(:collecting_metrics?, failing) { refute subscriber.silenced?("broken.test") }
      end

      it "leaves Active Support no event to build while no metric appender collects the metrics" do
        counting = Class.new(RailsSemanticLogger::Metrics::Subscriber) do
          const_set(:LOGGER_NAME, "CountingMetrics")
          attr_reader :events

          def counted(_event)
            @events = (@events || 0) + 1
          end
        end
        subscriber   = counting.new
        notifier     = ActiveSupport::Notifications::Fanout.new
        instrumenter = ActiveSupport::Notifications::Instrumenter.new(notifier)
        notifier.subscribe("counted.test", subscriber)

        counting.logger.stub(:collecting_metrics?, false) do
          refute notifier.listening?("counted.test")
          instrumenter.instrument("counted.test") { nil }
        end

        assert_nil subscriber.events

        counting.logger.stub(:collecting_metrics?, true) do
          assert notifier.listening?("counted.test")
          instrumenter.instrument("counted.test") { nil }
        end

        assert_equal 1, subscriber.events
      end

      it "never raises into the code that it instruments, and reports the first failure" do
        subscriber = subscriber_class.new
        event      = ActiveSupport::Notifications::Event.new("broken.test", Time.now, Time.now, "1", {})
        internal   = SemanticLogger::Test::CaptureLogEvents.new

        subscriber_class.logger.stub(:collecting_metrics?, true) do
          SemanticLogger::Processor.stub(:logger, internal) do
            subscriber.call(event)
            subscriber.call(event)
          end
        end

        assert_equal 1, internal.events.size
        assert_match(/BrokenMetrics failed to record a metric/, internal.events.first.message)
      end
    end
  end
end
