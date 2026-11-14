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

      # Rails' own Active Job log subscriber logs text lines with no payload, so this fails if
      # that subscriber is still attached, instead of or next to this gem's.
      it "logs the start and the finish once each, with a structured payload" do
        messages = semantic_logger_events do
          MyJob.perform_now("hello")
        end

        assert_equal %w[perform_start.active_job perform.active_job],
                     messages.map { |message| message.payload&.fetch(:event_name, nil) },
                     messages
        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          message_includes: "Performing ActiveJobTest::MyJob",
          payload_includes: {event_name: "perform_start.active_job", job_class: "ActiveJobTest::MyJob"}
        )
        assert_semantic_logger_event(
          messages[1],
          level:            :info,
          message_includes: "Performed ActiveJobTest::MyJob",
          payload_includes: {event_name: "perform.active_job", job_class: "ActiveJobTest::MyJob"}
        )
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
            metric:           "rails.job.perform",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "perform.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id

          exception = messages[0].exception

          assert_kind_of ArgumentError, exception
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
            message_includes: "Failed enqueuing ActiveJobTest::MyJob",
            metric:           "rails.job.enqueue",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id
          # As Rails words it: "Failed enqueuing <job> to <queue>: <exception class> (<message>)".
          assert_match(/ to Inline\(my_jobs\): ArgumentError \(error\)\z/, messages[0].message)

          exception = messages[0].exception

          assert_kind_of ArgumentError, exception
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
            level:            :info,
            name:             "Rails",
            message_includes: "Failed enqueuing ActiveJobTest::MyJob",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_match(/Failed enqueuing .*, a before_enqueue callback halted the enqueuing execution/,
                       messages[0].message)
          assert_includes messages[0].payload, :job_id
        end
      end

      describe "#enqueue_at with exception object" do
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
            subscriber.enqueue_at(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Failed enqueuing ActiveJobTest::MyJob",
            metric:           "rails.job.enqueue",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_includes messages[0].payload, :job_id
          # As Rails words it: "Failed enqueuing <job> to <queue>: <exception class> (<message>)".
          assert_match(/ to Inline\(my_jobs\): ArgumentError \(error\)\z/, messages[0].message)

          exception = messages[0].exception

          assert_kind_of ArgumentError, exception
          assert_equal "error", exception.message
        end
      end

      describe "#enqueue_at with throwing :abort" do
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
            subscriber.enqueue_at(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :info,
            name:             "Rails",
            message_includes: "Failed enqueuing ActiveJobTest::MyJob",
            payload_includes: {
              job_class:  "ActiveJobTest::MyJob",
              queue:      "my_jobs",
              event_name: "enqueue.active_job"
            }
          )
          assert_match(/Failed enqueuing .*, a before_enqueue callback halted the enqueuing execution/,
                       messages[0].message)
          assert_includes messages[0].payload, :job_id
        end
      end

      describe "#enqueue_all" do
        before do
          skip "enqueue_all requires Rails 7.1+" unless Rails.version.to_f >= 7.1
        end

        let(:event_name) { "enqueue_all.active_job" }

        let(:adapter) { ActiveJob::QueueAdapters::InlineAdapter.new }

        let(:jobs) { [MyJob.new("a"), MyJob.new("b")] }

        let(:enqueued_count) { jobs.size }

        let(:payload) do
          {
            adapter:        adapter,
            jobs:           jobs,
            enqueued_count: enqueued_count
          }
        end

        it "logs an info message with the enqueued count" do
          messages = semantic_logger_events do
            subscriber.enqueue_all(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :info,
            name:             "Rails",
            message_includes: "Enqueued 2 jobs to Inline",
            metric:           "rails.job.enqueue_all",
            payload_includes: {
              adapter:        "Inline",
              enqueued_count: 2,
              total_count:    2,
              event_name:     "enqueue_all.active_job"
            }
          )
          assert_equal({"ActiveJobTest::MyJob" => 2}, messages[0].payload[:job_classes])
        end

        describe "with partial failure" do
          let(:enqueued_count) { 1 }

          before do
            jobs[0].successfully_enqueued = true
            jobs[1].successfully_enqueued = false
          end

          it "logs an info message including the failed count" do
            messages = semantic_logger_events do
              subscriber.enqueue_all(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Failed enqueuing 1 job/, messages[0].message)
            assert_equal 1, messages[0].payload[:enqueued_count]
            assert_equal 2, messages[0].payload[:total_count]
          end
        end

        describe "with total failure" do
          let(:enqueued_count) { 0 }

          before do
            jobs.each { |job| job.successfully_enqueued = false }
          end

          it "logs an info message reporting all jobs failed" do
            messages = semantic_logger_events do
              subscriber.enqueue_all(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/\AFailed enqueuing 2 jobs to Inline/, messages[0].message)
            assert_equal 0, messages[0].payload[:enqueued_count]
          end
        end
      end

      describe "#enqueue_retry" do
        let(:event_name) { "enqueue_retry.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            error:   StandardError.new("boom"),
            wait:    5
          }
        end

        it "logs an info message with the retry details" do
          messages = semantic_logger_events do
            subscriber.enqueue_retry(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :info,
            name:             "Rails",
            message_includes: "Retrying ActiveJobTest::MyJob"
          )
          assert_match(/in 5 seconds, due to a StandardError \(boom\)\./, messages[0].message)
          assert_instance_of StandardError, messages[0].exception
          assert_equal 5, messages[0].payload[:wait]
          assert_includes messages[0].payload, :executions
        end
      end

      describe "#retry_stopped" do
        let(:event_name) { "retry_stopped.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            error:   StandardError.new("boom")
          }
        end

        it "logs an error message" do
          messages = semantic_logger_events do
            subscriber.retry_stopped(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Stopped retrying ActiveJobTest::MyJob"
          )
          assert_instance_of StandardError, messages[0].exception
          assert_includes messages[0].payload, :executions
        end
      end

      describe "#discard" do
        let(:event_name) { "discard.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            error:   StandardError.new("boom")
          }
        end

        it "logs an error message" do
          messages = semantic_logger_events do
            subscriber.discard(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "Rails",
            message_includes: "Discarded ActiveJobTest::MyJob"
          )
          assert_instance_of StandardError, messages[0].exception
        end
      end

      describe "#enqueue_retry without an error" do
        let(:event_name) { "enqueue_retry.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            wait:    3
          }
        end

        it "logs the retry without a cause" do
          messages = semantic_logger_events do
            subscriber.enqueue_retry(event)
          end

          assert_equal 1, messages.count, messages
          assert_equal :info, messages[0].level
          assert_match(/Retrying ActiveJobTest::MyJob.* in 3 seconds\.\z/, messages[0].message)
          refute_match(/due to a/, messages[0].message)
          assert_nil messages[0].exception
          assert_equal 3, messages[0].payload[:wait]
        end
      end

      describe "#perform with a halted callback" do
        let(:event_name) { "perform.active_job" }

        let(:payload) do
          {
            adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
            job:     job,
            aborted: true
          }
        end

        it "logs an error message reporting the halt" do
          messages = semantic_logger_events do
            subscriber.perform(event)
          end

          assert_equal 1, messages.count, messages
          assert_equal :error, messages[0].level
          assert_match(/a before_perform callback halted the job execution/, messages[0].message)
          assert_nil messages[0].exception
        end
      end

      describe "#enqueue with job.enqueue_error" do
        let(:event_name) { "enqueue.active_job" }

        it "falls back to the job's enqueue_error" do
          job.stub(:enqueue_error, StandardError.new("could not enqueue")) do
            messages = semantic_logger_events do
              subscriber.enqueue(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :error, messages[0].level
            assert_match(/Failed enqueuing ActiveJobTest::MyJob/, messages[0].message)
            assert_instance_of StandardError, messages[0].exception
            assert_equal "could not enqueue", messages[0].exception.message
          end
        end
      end

      describe "ActiveJob Continuations (Rails 8.1+)" do
        before do
          skip "Continuations require Rails 8.1+" unless Rails.version.to_f >= 8.1
        end

        unless defined?(Step)
          Step = Struct.new(:name, :cursor, :resumed) do
            def resumed?
              resumed
            end
          end
        end

        describe "#interrupt" do
          let(:event_name) { "interrupt.active_job" }

          let(:payload) do
            {
              adapter:     ActiveJob::QueueAdapters::InlineAdapter.new,
              job:         job,
              description: "at step 'one'",
              reason:      "shutdown"
            }
          end

          it "logs an info message" do
            messages = semantic_logger_events do
              subscriber.interrupt(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Interrupted ActiveJobTest::MyJob/, messages[0].message)
            assert_equal "shutdown", messages[0].payload[:reason]
          end
        end

        describe "#resume" do
          let(:event_name) { "resume.active_job" }

          let(:payload) do
            {
              adapter:     ActiveJob::QueueAdapters::InlineAdapter.new,
              job:         job,
              description: "from step 'one'"
            }
          end

          it "logs an info message" do
            messages = semantic_logger_events do
              subscriber.resume(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Resuming ActiveJobTest::MyJob/, messages[0].message)
          end
        end

        describe "#step_started" do
          let(:event_name) { "step_started.active_job" }

          let(:payload) do
            {
              adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
              job:     job,
              step:    Step.new("one", nil, false)
            }
          end

          it "logs an info message with the step name" do
            messages = semantic_logger_events do
              subscriber.step_started(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Step 'one' started/, messages[0].message)
            assert_equal "one", messages[0].payload[:step_name]
          end
        end

        describe "#step_skipped" do
          let(:event_name) { "step_skipped.active_job" }

          let(:payload) do
            {
              adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
              job:     job,
              step:    Step.new("one", nil, false)
            }
          end

          it "logs an info message" do
            messages = semantic_logger_events do
              subscriber.step_skipped(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Step 'one' skipped/, messages[0].message)
            assert_equal "one", messages[0].payload[:step_name]
          end
        end

        describe "#step_started when resumed" do
          let(:event_name) { "step_started.active_job" }

          let(:payload) do
            {
              adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
              job:     job,
              step:    Step.new("one", "5", true)
            }
          end

          it "logs that the step resumed from its cursor" do
            messages = semantic_logger_events do
              subscriber.step_started(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Step 'one' resumed from cursor '5'/, messages[0].message)
            assert_equal "5", messages[0].payload[:step_cursor]
          end
        end

        describe "#step with exception" do
          let(:event_name) { "step.active_job" }

          let(:payload) do
            {
              adapter:          ActiveJob::QueueAdapters::InlineAdapter.new,
              job:              job,
              step:             Step.new("one", "5", true),
              exception_object: StandardError.new("boom")
            }
          end

          it "logs an error message with the cursor" do
            messages = semantic_logger_events do
              subscriber.step(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :error, messages[0].level
            assert_match(/Error during step 'one' at cursor '5'/, messages[0].message)
            assert_equal "5", messages[0].payload[:step_cursor]
            assert_instance_of StandardError, messages[0].exception
          end
        end

        describe "#step when interrupted" do
          let(:event_name) { "step.active_job" }

          let(:payload) do
            {
              adapter:     ActiveJob::QueueAdapters::InlineAdapter.new,
              job:         job,
              step:        Step.new("one", "5", true),
              interrupted: true
            }
          end

          it "logs an info message reporting the interruption" do
            messages = semantic_logger_events do
              subscriber.step(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Step 'one' interrupted at cursor '5'/, messages[0].message)
            assert_nil messages[0].exception
          end
        end

        describe "#step when completed" do
          let(:event_name) { "step.active_job" }

          let(:payload) do
            {
              adapter: ActiveJob::QueueAdapters::InlineAdapter.new,
              job:     job,
              step:    Step.new("one", "5", true)
            }
          end

          it "logs an info message reporting completion" do
            messages = semantic_logger_events do
              subscriber.step(event)
            end

            assert_equal 1, messages.count, messages
            assert_equal :info, messages[0].level
            assert_match(/Step 'one' completed/, messages[0].message)
            assert_includes messages[0].payload, :duration
          end
        end
      end

      describe ".backtrace_cleaner" do
        it "is the application's backtrace cleaner" do
          assert_same Rails.backtrace_cleaner, RailsSemanticLogger::ActiveJob::LogSubscriber.backtrace_cleaner
        end
      end

      describe "verbose_enqueue_logs" do
        before do
          @verbose_enqueue_logs           = ActiveJob.verbose_enqueue_logs
          ActiveJob.verbose_enqueue_logs  = true
          # The application's cleaner has no silencers in these tests (see test_helper.rb), and none at
          # all when BACKTRACE is set. This one keeps only this file's frames, so that the source is the
          # line in this file that enqueued the job.
          subscriber.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
            cleaner.remove_filters!
            cleaner.add_silencer { |line| !line.start_with?("#{__FILE__}:") }
          end
        end

        after do
          ActiveJob.verbose_enqueue_logs = @verbose_enqueue_logs
        end

        def new_event(name, payload)
          ActiveSupport::Notifications::Event.new(name, 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload)
        end

        def assert_source(line, message)
          assert_match(/\A#{Regexp.escape(__FILE__)}:#{line}:in /, message.payload[:source], message.payload)
        end

        it "logs the code that enqueued the job as the source of an enqueue" do
          line     = __LINE__ + 1
          messages = semantic_logger_events { subscriber.enqueue(event) }

          assert_equal 1, messages.count, messages
          assert_source line, messages[0]
        end

        it "logs the code that enqueued the job as the source of an enqueue_at" do
          event    = new_event("enqueue_at.active_job", payload)
          line     = __LINE__ + 2
          messages = job.stub(:scheduled_at, Time.zone.now.to_i) do
            semantic_logger_events { subscriber.enqueue_at(event) }
          end

          assert_equal 1, messages.count, messages
          assert_source line, messages[0]
        end

        it "logs the code that enqueued the jobs as the source of an enqueue_all" do
          event = new_event(
            "enqueue_all.active_job",
            {adapter: ActiveJob::QueueAdapters::InlineAdapter.new, jobs: [MyJob.new("a")], enqueued_count: 1}
          )
          line     = __LINE__ + 1
          messages = semantic_logger_events { subscriber.enqueue_all(event) }

          assert_equal 1, messages.count, messages
          assert_source line, messages[0]
        end

        it "logs the source of a halted enqueue" do
          aborted  = new_event("enqueue.active_job", payload.merge(aborted: true))
          line     = __LINE__ + 1
          messages = semantic_logger_events { subscriber.enqueue(aborted) }

          assert_equal 1, messages.count, messages
          assert_source line, messages[0]
        end

        it "logs the source of an enqueue that failed with an error" do
          failed   = new_event("enqueue.active_job", payload.merge(exception_object: StandardError.new("boom")))
          line     = __LINE__ + 1
          messages = semantic_logger_events { subscriber.enqueue(failed) }

          assert_equal 1, messages.count, messages
          assert_equal :error, messages[0].level
          assert_source line, messages[0]
        end

        # As for a job performed inline, such as with perform_now. A worker's call stack has no
        # application frame outside the job, so its perform_start and perform entries get no source.
        it "logs the code that performed the job inline as the source of a perform" do
          started  = new_event("perform_start.active_job", payload)
          line     = __LINE__ + 1
          messages = semantic_logger_events { subscriber.perform_start(started) }

          assert_equal 1, messages.count, messages
          assert_source line, messages[0]
        end

        describe "when the logger would not log the entry" do
          # Counts the frames the cleaner looks at while the block runs.
          def frames_cleaned
            frames = 0
            subscriber.backtrace_cleaner.add_silencer do
              frames += 1
              false
            end
            yield
            frames
          end

          let(:failed) { new_event("enqueue.active_job", payload.merge(exception_object: StandardError.new("boom"))) }

          it "does not look for the source of an info entry" do
            frames = frames_cleaned do
              ActiveJob::Base.logger.stub(:info?, false) { subscriber.enqueue(event) }
            end

            assert_equal 0, frames
          end

          it "does not look for the source of an enqueue_all" do
            event  = new_event(
              "enqueue_all.active_job",
              {adapter: ActiveJob::QueueAdapters::InlineAdapter.new, jobs: [MyJob.new("a")], enqueued_count: 1}
            )
            frames = frames_cleaned do
              ActiveJob::Base.logger.stub(:info?, false) { subscriber.enqueue_all(event) }
            end

            assert_equal 0, frames
          end

          it "does not look for the source of an error entry" do
            frames = frames_cleaned do
              ActiveJob::Base.logger.stub(:error?, false) { subscriber.enqueue(failed) }
            end

            assert_equal 0, frames
          end

          it "still logs the source of an error entry when only info is off" do
            line     = __LINE__ + 2
            messages = ActiveJob::Base.logger.stub(:info?, false) do
              semantic_logger_events { subscriber.enqueue(failed) }
            end

            assert_equal 1, messages.count, messages
            assert_source line, messages[0]
          end
        end

        it "logs no source when it is off" do
          ActiveJob.verbose_enqueue_logs = false

          messages = semantic_logger_events { subscriber.enqueue(event) }

          assert_equal 1, messages.count, messages
          refute messages[0].payload.key?(:source), messages[0].payload
        end
      end

      describe "ActiveJob::Logging::LogSubscriber::EventFormatter" do
        let(:formatter) do
          RailsSemanticLogger::ActiveJob::LogSubscriber::EventFormatter.new(event: event, log_duration: true)
        end

        let(:event_name) { "perform.active_job" }

        describe "#payload" do
          specify do
            assert_equal("perform.active_job", formatter.payload[:event_name])
            assert_equal("Inline", formatter.payload[:adapter])
            assert_equal("my_jobs", formatter.payload[:queue])
            assert_kind_of(String, formatter.payload[:job_id])
            assert_kind_of(Float, formatter.payload[:duration])
          end

          describe "scheduled_at" do
            it "is omitted when the job is not scheduled" do
              refute_includes formatter.payload, :scheduled_at
            end

            it "is included when the job is scheduled" do
              job.stub(:scheduled_at, Time.zone.now.to_i) do
                assert_kind_of Time, formatter.payload[:scheduled_at]
              end
            end
          end

          describe "enqueued_at" do
            it "is omitted when blank" do
              refute_includes formatter.payload, :enqueued_at
            end

            it "is included when present" do
              job.stub(:enqueued_at, Time.zone.now.utc.iso8601) do
                assert formatter.payload[:enqueued_at]
              end
            end
          end

          describe "Show arguments in log" do
            let(:job) do
              MyJob.new(TestModel.new, 1, "string", foo: "bar")
            end

            specify do
              assert_equal("ActiveJobTest::MyJob", formatter.payload[:job_class])
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
              assert_equal("ActiveJobTest::SensitiveJob", formatter.payload[:job_class])
              assert_equal("", formatter.payload[:arguments])
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
            assert_equal("Inline(my_jobs)", formatter.queue_name)
          end
        end
      end
    end
  end
end
