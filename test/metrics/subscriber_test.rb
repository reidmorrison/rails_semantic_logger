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
