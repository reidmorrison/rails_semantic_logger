require_relative "test_helper"

class ActiveJobTest < Minitest::Test
  if defined?(ActiveJob)
    class MyJob < ActiveJob::Base
      queue_as :my_jobs

      def perform(record)
        "Received: #{record}"
      end
    end

    class SensitiveJob < ActiveJob::Base
      queue_as :my_jobs

      if Rails.version.to_f >= 6.1
        self.log_arguments = false
      else
        def self.log_arguments?
          false
        end
      end

      def perform(record)
        "Received: #{record}"
      end
    end

    class TestModel
      include GlobalID::Identification

      def id
        15
      end
    end
  end

  describe "ActiveJob" do
    before do
      skip "Older rails does not support ActiveJob" unless defined?(ActiveJob)
    end

    describe ".perform_now" do
      it "sets the ActiveJob logger" do
        assert_kind_of SemanticLogger::Logger, MyJob.logger
      end

      it "runs the job" do
        MyJob.perform_now("hello")
      end
    end

    describe "Logging::LogSubscriber" do
      before do
        skip "Older rails does not support ActiveSupport::Notification" unless defined?(ActiveSupport::Notifications)
      end

      let(:subscriber) { RailsSemanticLogger::ActiveJob::LogSubscriber.new }

      let(:event) do
        ActiveSupport::Notifications::Event.new(event_name, 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload)
      end

      let(:event_name) { "enqueue.active_job" }

      let(:payload) do
        {
          adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
          job:     job
        }
      end

      let(:job) do
        MyJob.new(TestModel.new, 1, "string", foo: "bar")
      end

      %i[enqueue enqueue_at perform_start perform].each do |method|
        describe "##{method}" do
          specify do
            job.stub(:scheduled_at, Time.zone.now.to_i) do
              assert ActiveJob::Base.logger.info
              subscriber.public_send(method, event)
            end
          end
        end
      end

      describe "#perform with exception object" do
        let(:event_name) { "perform.active_job" }

        let(:payload) do
          {
            adapter:          ActiveJob::QueueAdapters::InlineAdapter.new,
            job:              job,
            exception_object: ArgumentError.new("error")
          }
        end

        it "logs messages" do
          messages = semantic_logger_events do
            subscriber.perform(event)
          end
          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Error performing ActiveJobTest::MyJob",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "perform.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id

          exception = messages[0].exception
          assert exception.is_a?(ArgumentError)
          assert_equal "error", exception.message
        end
      end

      describe "#enqueue with exception object" do
        let(:event_name) { "enqueue.active_job" }

        let(:payload) do
          {
            adapter:          ActiveJob::QueueAdapters::InlineAdapter.new,
            job:              job,
            exception_object: ArgumentError.new("error")
          }
        end

        it "logs message" do
          messages = semantic_logger_events do
            subscriber.enqueue(event)
          end
          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Error enqueuing ActiveJobTest::MyJob",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id

          exception = messages[0].exception
          assert exception.is_a?(ArgumentError)
          assert_equal "error", exception.message
        end
      end

      describe "#enqueue with throwing :abort" do
        let(:event_name) { "enqueue.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            aborted: true
          }
        end

        it "logs message" do
          messages = semantic_logger_events do
            subscriber.enqueue(event)
          end
          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Failed enqueuing ActiveJobTest::MyJob, a before_enqueue callback halted the enqueuing execution.",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id
        end
      end

      describe "ActiveJob::Logging::LogSubscriber::EventFormatter" do
        let(:formatter) do
          RailsSemanticLogger::ActiveJob::LogSubscriber::EventFormatter.new(event: event, log_duration: true)
        end

        let(:event_name) { "perform.active_job" }

        describe "#payload" do
          specify do
            assert_equal(formatter.payload[:event_name], "perform.active_job")
            assert_equal(formatter.payload[:adapter], "Inline")
            assert_equal(formatter.payload[:queue], "my_jobs")
            assert_kind_of(String, formatter.payload[:job_id])
            assert_kind_of(Float, formatter.payload[:duration])
          end

          describe "Show arguments in log" do
            let(:job) do
              MyJob.new(TestModel.new, 1, "string", foo: "bar")
            end

            specify do
              assert_equal(formatter.payload[:job_class], "ActiveJobTest::MyJob")
              arguments = <<~ARGS.chomp
                [
                  "gid://dummy/ActiveJobTest::TestModel/15",
                  1,
                  "string",
                  {
                    "foo": "bar"
                  }
                ]
              ARGS
              assert_equal(formatter.payload[:arguments], arguments)
            end
          end

          describe "Hide arguments from log" do
            let(:job) do
              SensitiveJob.new(TestModel.new, 1, "string", foo: "bar")
            end

            specify do
              assert_equal(formatter.payload[:job_class], "ActiveJobTest::SensitiveJob")
              assert_equal(formatter.payload[:arguments], "")
            end
          end
        end

        describe "#job_info" do
          specify do
            assert_match(/^ActiveJobTest::MyJob \(Job ID: [a-z\-0-9]+\) to Inline\(my_jobs\)$/, formatter.job_info)
          end
        end

        describe "#queue_name" do
          specify do
            assert_equal(formatter.queue_name, "Inline(my_jobs)")
          end
        end
      end
    end
  end
end
