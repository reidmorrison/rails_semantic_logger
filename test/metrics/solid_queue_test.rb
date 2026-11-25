require_relative "../test_helper"

module Metrics
  class SolidQueueTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::SolidQueue do
      it "records through the logger of Solid Queue, whose name is the meter" do
        assert_equal "SolidQueue", RailsSemanticLogger::Metrics::SolidQueue.logger.name
      end

      let(:subscriber) { RailsSemanticLogger::Metrics::SolidQueue.new }

      def record(name, payload)
        event = ActiveSupport::Notifications::Event.new("#{name}.solid_queue", 5.seconds.ago, Time.zone.now, "1",
                                                        payload)
        semantic_logger_metrics { subscriber.public_send(name, event) }
      end

      it "records each operation by name, whatever its log level" do
        metric = assert_metric(
          record(:claim, process_id: 42, job_ids: [1], claimed_job_ids: [1], size: 1),
          name:       "solid_queue.operation.duration",
          kind:       :histogram,
          unit:       "s",
          dimensions: {"solid_queue.operation.name" => "claim"}
        )

        assert_in_delta 5, metric.value, 0.5
      end

      it "records the class of a reported error" do
        assert_metric(
          record(:thread_error, error: RuntimeError.new("boom")),
          name:       "solid_queue.operation.duration",
          dimensions: {"solid_queue.operation.name" => "thread_error", "error.type" => "RuntimeError"}
        )
      end

      it "records the class of an exception the operation raised" do
        assert_metric(
          record(:start_process, exception: ["ActiveRecord::ConnectionNotEstablished", "down"]),
          name:       "solid_queue.operation.duration",
          dimensions: {"solid_queue.operation.name" => "start_process", "error.type" => "ActiveRecord::ConnectionNotEstablished"}
        )
      end

      it "records a recurring task that failed to enqueue its job as an error" do
        assert_metric(
          record(:enqueue_recurring_task, task: "cleanup", active_job_id: nil, enqueue_error: "boom"),
          name:       "solid_queue.operation.duration",
          dimensions: {"solid_queue.operation.name" => "enqueue_recurring_task", "error.type" => "enqueue_error"}
        )
      end

      it "records no error.type for the jobs that fail_many_claimed failed" do
        metric = assert_metric(
          record(:fail_many_claimed, job_ids: [1], process_ids: [2], error: RuntimeError.new("pruned")),
          name: "solid_queue.operation.duration"
        )

        refute metric.dimensions.key?("error.type")
      end

      # Solid Queue's log subscriber has no handler for polling and replace_thread, which EVENTS lists
      # by hand, so this catches only a new event that Solid Queue also logs.
      it "subscribes to every event that Solid Queue's own log subscriber logs" do
        skip "SolidQueue is not available" unless defined?(::SolidQueue::LogSubscriber)

        logged = ::SolidQueue::LogSubscriber.public_instance_methods(false).map(&:to_s)

        assert_empty logged - RailsSemanticLogger::Metrics::SolidQueue::EVENTS
      end
    end
  end
end
