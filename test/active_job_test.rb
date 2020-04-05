require_relative "test_helper"

class ActiveJobTest < Minitest::Test
  if defined?(ActiveJob)
    class MyJob < ActiveJob::Base
      queue_as :my_jobs

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
        ActiveSupport::Notifications::Event.new "enqueue.active_job",
                                                5.seconds.ago,
                                                Time.zone.now,
                                                SecureRandom.uuid,
                                                adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
                                                job:     job
      end

      let(:job) do
        MyJob.new(TestModel.new, 1, "string", foo: "bar")
      end

      %i[enqueue enqueue_at perform_start perform].each do |method|
        describe "##{method}" do
          specify do
            job.stub(:scheduled_at, Time.zone.now.to_i) do
              assert_send([ActiveJob::Base.logger, :info])
              subscriber.public_send(method, event)
            end
          end
        end
      end

      describe "ActiveJob::Logging::LogSubscriber::EventFormatter" do
        let(:formatter) do
          RailsSemanticLogger::ActiveJob::LogSubscriber::EventFormatter.new(event: event, log_duration: true)
        end

        let(:event) do
          ActiveSupport::Notifications::Event.new "perform.active_job",
                                                  5.seconds.ago,
                                                  Time.zone.now,
                                                  "transaction_id",
                                                  adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
                                                  job:     MyJob.new(TestModel.new, 1, "string", foo: "bar")
        end

        describe "#payload" do
          specify do
            assert_equal(formatter.payload[:event_name], "perform.active_job")
            assert_equal(formatter.payload[:adapter], "Inline")
            assert_equal(formatter.payload[:queue], "my_jobs")
            assert_equal(formatter.payload[:job_class], "ActiveJobTest::MyJob")
            assert_kind_of(String, formatter.payload[:job_id])
            assert_kind_of(Float, formatter.payload[:duration])
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
