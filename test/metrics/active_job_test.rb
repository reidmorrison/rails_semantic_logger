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

        it "records no queue duration for a job that was never enqueued" do
          metrics = semantic_logger_metrics { ReportJob.perform_now }

          assert_empty(metrics.select { |metric| metric.name == "active_job.queue.duration" })
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
