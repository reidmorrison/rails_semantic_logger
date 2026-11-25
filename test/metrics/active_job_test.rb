require_relative "../test_helper"

module Metrics
  class ActiveJobTest < Minitest::Test
    class ReportJob < ::ActiveJob::Base
      self.queue_adapter = :test
      queue_as :reports

      def perform(fail: false)
        raise ArgumentError, "boom" if fail
      end
    end

    describe RailsSemanticLogger::Metrics::ActiveJob do
      it "records through the logger of Active Job, whose name is the meter" do
        assert_equal "ActiveJob::Base", RailsSemanticLogger::Metrics::ActiveJob.logger.name
      end

      let(:job_dimensions) do
        {
          "messaging.system.name"          => "active_job",
          "messaging.destination.name"     => "reports",
          "messaging.active_job.job.class" => "Metrics::ActiveJobTest::ReportJob"
        }
      end

      describe "enqueuing" do
        it "counts the job as sent and times the enqueue" do
          metrics = semantic_logger_metrics { ReportJob.perform_later }

          assert_metric(metrics, name: "messaging.client.sent.messages", kind: :counter, value: 1,
dimensions: job_dimensions)
          assert_metric(
            metrics,
            name:       "messaging.client.operation.duration",
            kind:       :histogram,
            unit:       "s",
            dimensions: job_dimensions.merge(
              "messaging.operation.name"          => "enqueue",
              "messaging.operation.type"          => "send",
              "messaging.active_job.adapter.name" => "Test"
            )
          )
        end

        it "names a scheduled enqueue enqueue_at" do
          metrics = semantic_logger_metrics { ReportJob.set(wait: 1.minute).perform_later }

          metric = assert_metric(metrics, name: "messaging.client.operation.duration")

          assert_equal "enqueue_at", metric.dimensions["messaging.operation.name"]
        end
      end

      describe "performing" do
        it "records how long the job ran" do
          metrics = semantic_logger_metrics { ReportJob.perform_now }

          assert_metric(
            metrics,
            name:       "messaging.process.duration",
            kind:       :histogram,
            unit:       "s",
            dimensions: job_dimensions.merge("messaging.operation.name" => "process")
          )
        end

        it "records the exception class of a job that raised" do
          metrics = semantic_logger_metrics do
            assert_raises(ArgumentError) { ReportJob.perform_now(fail: true) }
          end

          metric = assert_metric(metrics, name: "messaging.process.duration")

          assert_equal "ArgumentError", metric.dimensions["error.type"]
        end

        it "records how long the job waited in its queue" do
          job             = ReportJob.new
          job.enqueued_at = 60.seconds.ago

          metrics = semantic_logger_metrics { job.perform_now }

          latency = assert_metric(metrics, name: "active_job.queue.duration", kind: :histogram,
dimensions: job_dimensions)

          assert_in_delta 60, latency.value, 5
        end

        it "records the queue duration from when a scheduled job was due" do
          job              = ReportJob.new
          job.enqueued_at  = 10.minutes.ago
          job.scheduled_at = 60.seconds.ago

          latency = assert_metric(semantic_logger_metrics { job.perform_now }, name: "active_job.queue.duration")

          assert_in_delta 60, latency.value, 5
        end

        it "records the queue duration from when a job that ran as scheduled was enqueued again" do
          job              = ReportJob.new
          job.scheduled_at = 2.hours.ago
          job.enqueued_at  = 60.seconds.ago

          latency = assert_metric(semantic_logger_metrics { job.perform_now }, name: "active_job.queue.duration")

          assert_in_delta 60, latency.value, 5
        end

        it "records no queue duration for a job performed at once with a wait" do
          metrics = semantic_logger_metrics { ReportJob.set(wait_until: Date.tomorrow).perform_now }

          assert_empty(metrics.select { |metric| metric.name == "active_job.queue.duration" })
        end

        it "records no queue duration for a job that was never enqueued" do
          metrics = semantic_logger_metrics { ReportJob.perform_now }

          assert_empty(metrics.select { |metric| metric.name == "active_job.queue.duration" })
        end
      end

      describe "enqueue_all" do
        let(:subscriber) { RailsSemanticLogger::Metrics::ActiveJob.new }
        let(:jobs) { [ReportJob.new, ReportJob.new] }

        def record(payload)
          event = ActiveSupport::Notifications::Event.new("enqueue_all.active_job", Time.now, Time.now, "1", payload)
          semantic_logger_metrics { subscriber.enqueue_all(event) }
        end

        it "counts every job when an adapter enqueued them all without marking them, as Sidekiq's does" do
          metrics = record(jobs: jobs, enqueued_count: 2)

          assert_metric(metrics, name: "messaging.client.sent.messages", value: 2, dimensions: job_dimensions)
          duration = assert_metric(metrics, name: "messaging.client.operation.duration")

          refute duration.dimensions.key?("error.type")
        end

        it "counts only the jobs marked as enqueued when some failed" do
          jobs.first.successfully_enqueued = true
          metrics = record(jobs: jobs, enqueued_count: 1)

          assert_metric(metrics, name: "messaging.client.sent.messages", value: 1)
          assert_equal "partial",
                       assert_metric(metrics, name: "messaging.client.operation.duration").dimensions["error.type"]
        end

        it "counts the enqueued count when an adapter marked none of the jobs it enqueued" do
          metrics = record(jobs: jobs, enqueued_count: 1)

          assert_metric(metrics, name: "messaging.client.sent.messages", value: 1, dimensions: job_dimensions)
          assert_equal "partial",
                       assert_metric(metrics, name: "messaging.client.operation.duration").dimensions["error.type"]
        end

        it "counts the adapter's count when a job keeps the mark of an earlier enqueue" do
          jobs.first.successfully_enqueued = true
          metrics = record(jobs: jobs + [ReportJob.new], enqueued_count: 2)

          assert_metric(metrics, name: "messaging.client.sent.messages", value: 2, dimensions: job_dimensions)
        end

        it "records failed when no job was enqueued" do
          metrics = record(jobs: jobs, enqueued_count: 0)

          assert_empty(metrics.select { |metric| metric.name == "messaging.client.sent.messages" })
          assert_equal "failed",
                       assert_metric(metrics, name: "messaging.client.operation.duration").dimensions["error.type"]
        end

        it "records the exception class when enqueuing raised" do
          metrics = record(jobs: jobs, exception_object: IOError.new("down"))

          assert_equal "IOError",
                       assert_metric(metrics, name: "messaging.client.operation.duration").dimensions["error.type"]
        end
      end

      describe "a continuation step" do
        let(:subscriber) { RailsSemanticLogger::Metrics::ActiveJob.new }
        let(:step) { Struct.new(:name).new(:process_rows) }

        def record(payload)
          event = ActiveSupport::Notifications::Event.new("step.active_job", Time.now, Time.now, "1",
                                                          {job: ReportJob.new, step: step}.merge(payload))
          semantic_logger_metrics { subscriber.step(event) }
        end

        it "records an interrupted step as interrupted, not as an error" do
          metric = assert_metric(record(interrupted: true, exception_object: RuntimeError.new("interrupt")),
                                 name: "active_job.step.duration")

          assert metric.dimensions["active_job.step.interrupted"]
          refute metric.dimensions.key?("error.type")
        end

        it "records the error.type of a step that raised" do
          metric = assert_metric(record(interrupted: false, exception_object: ArgumentError.new("boom")),
                                 name: "active_job.step.duration")

          refute metric.dimensions["active_job.step.interrupted"]
          assert_equal "ArgumentError", metric.dimensions["error.type"]
          assert_equal "process_rows", metric.dimensions["active_job.step.name"]
        end
      end

      it "counts retries, exhausted retries and discards by job and error" do
        job        = ReportJob.new
        error      = ArgumentError.new("boom")
        subscriber = RailsSemanticLogger::Metrics::ActiveJob.new
        expected   = job_dimensions.merge("error.type" => "ArgumentError")

        {enqueue_retry: "active_job.retries", retry_stopped: "active_job.exhausted_retries",
discard: "active_job.discards"}.each do |event, name|
          notification = ActiveSupport::Notifications::Event.new("#{event}.active_job", Time.now, Time.now, "1",
                                                                 {job: job, error: error})
          metrics = semantic_logger_metrics { subscriber.public_send(event, notification) }

          assert_metric(metrics, name: name, kind: :counter, value: 1, dimensions: expected)
        end
      end
    end
  end
end
