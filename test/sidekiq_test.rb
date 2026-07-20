require_relative "test_helper"

class SidekiqTest < Minitest::Test
  # Cannot use inline testing since it bypasses the Sidekiq logging calls.
  describe Sidekiq::Worker do
    let(:job) { SimpleJob }
    let(:args) { [] }

    describe "#logger" do
      it "has its own logger with the same name as the job" do
        assert_kind_of SemanticLogger::Logger, SimpleJob.logger
        assert_kind_of SemanticLogger::Logger, job.logger
        assert_equal job.logger.name, job.name
        refute_same Sidekiq.logger, job.logger
      end
    end

    describe "#perform" do
      let(:config) { Sidekiq.default_configuration }
      let(:msg) { Sidekiq.dump_json({"class" => job.to_s, "args" => args, "enqueued_at" => (Time.now - 60).to_f}) }
      let(:uow) { Sidekiq::BasicFetch::UnitOfWork.new("queue:default", msg) }
      # Sidekiq requires a callback block; the tests never exercise it.
      let(:processor) do
        Sidekiq::Processor.new(config.default_capsule) { |*_args| nil }
      end

      it "a simple job" do
        # SimpleJob.perform_async
        messages = semantic_logger_events do
          processor.send(:process, uow)
        end

        assert_equal 2, messages.count, -> { messages.collect(&:to_h).ai }

        assert_semantic_logger_event(
          messages[0],
          level:      :info,
          name:       "SimpleJob",
          message:    "Start #perform",
          metric:     "sidekiq.queue.latency",
          named_tags: {jid: nil, class: "SimpleJob", queue: "default"}
        )
        assert_kind_of Float, messages[0].metric_amount

        assert_semantic_logger_event(
          messages[1],
          level:      :info,
          name:       "SimpleJob",
          message:    "Completed #perform",
          metric:     "sidekiq.job.perform",
          named_tags: {jid: nil, class: "SimpleJob", queue: "default"}
        )
        assert_kind_of Float, messages[1].duration
      end

      it "a simple job with Sidekiq 8+ timestamp (milliseconds)" do
        # Sidekiq 8+ stores enqueued_at as milliseconds since epoch (Integer)
        enqueued_at_ms = (Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond) - 60_000).to_i
        msg_sidekiq8 = Sidekiq.dump_json({"class" => job.to_s, "args" => args, "enqueued_at" => enqueued_at_ms})
        uow_sidekiq8 = Sidekiq::BasicFetch::UnitOfWork.new("queue:default", msg_sidekiq8)

        messages = semantic_logger_events do
          processor.send(:process, uow_sidekiq8)
        end

        assert_equal 2, messages.count, -> { messages.collect(&:to_h).ai }

        assert_semantic_logger_event(
          messages[0],
          level:      :info,
          name:       "SimpleJob",
          message:    "Start #perform",
          metric:     "sidekiq.queue.latency",
          named_tags: {jid: nil, class: "SimpleJob", queue: "default"}
        )
        # Sidekiq 8+ returns Integer latency, whereas earlier versions return Float
        assert_kind_of Numeric, messages[0].metric_amount

        assert_semantic_logger_event(
          messages[1],
          level:      :info,
          name:       "SimpleJob",
          message:    "Completed #perform",
          metric:     "sidekiq.job.perform",
          named_tags: {jid: nil, class: "SimpleJob", queue: "default"}
        )
        assert_kind_of Float, messages[1].duration
      end

      it "does not emit perform messages when disabled" do
        RailsSemanticLogger::Sidekiq::JobLogger.perform_messages = false

        messages = semantic_logger_events do
          processor.send(:process, uow)
        end

        assert_equal 0, messages.count, -> { messages.collect(&:to_h).ai }
      ensure
        RailsSemanticLogger::Sidekiq::JobLogger.perform_messages = true
      end

      # Sidekiq 8 passes its config to the job logger, making these options available.
      if Sidekiq::VERSION.to_i >= 8
        it "does not emit perform messages when skip_default_job_logging is set" do
          config[:skip_default_job_logging] = true

          messages = semantic_logger_events do
            processor.send(:process, uow)
          end

          assert_equal 0, messages.count, -> { messages.collect(&:to_h).ai }
        ensure
          config[:skip_default_job_logging] = false
        end

        it "adds logged_job_attributes from the Sidekiq config to the logging context" do
          config[:logged_job_attributes] = %w[bid tags priority]
          msg_with_priority = Sidekiq.dump_json(
            {"class" => job.to_s, "args" => args, "enqueued_at" => (Time.now - 60).to_f, "priority" => "high"}
          )
          uow_with_priority = Sidekiq::BasicFetch::UnitOfWork.new("queue:default", msg_with_priority)

          messages = semantic_logger_events do
            processor.send(:process, uow_with_priority)
          end

          assert_equal 2, messages.count, -> { messages.collect(&:to_h).ai }

          assert_semantic_logger_event(
            messages[0],
            level:      :info,
            name:       "SimpleJob",
            message:    "Start #perform",
            named_tags: {jid: nil, class: "SimpleJob", priority: "high", queue: "default"}
          )
        ensure
          config[:logged_job_attributes] = %w[bid tags]
        end
      end

      describe "with Bad Job" do
        let(:job) { BadJob }

        it "a job that raises an exception" do
          # BadJob.perform_async
          messages = semantic_logger_events do
            assert_raises ArgumentError do
              processor.send(:process, uow)
            end
          end

          assert_equal 3, messages.count, -> { messages.collect(&:to_h).ai }

          assert_semantic_logger_event(
            messages[0],
            level:      :info,
            name:       "BadJob",
            message:    "Start #perform",
            metric:     "sidekiq.queue.latency",
            named_tags: {jid: nil, class: "BadJob", queue: "default"},
            exception:  :nil
          )
          assert_kind_of Float, messages[0].metric_amount

          assert_semantic_logger_event(
            messages[1],
            level:      :error,
            name:       "BadJob",
            message:    "Completed #perform",
            metric:     "sidekiq.job.perform",
            named_tags: {jid: nil, class: "BadJob", queue: "default"},
            exception:  ArgumentError
          )
          assert_kind_of Float, messages[1].duration

          assert_semantic_logger_event(
            messages[2],
            level:            :info,
            name:             "BadJob",
            message:          "Job raised exception",
            payload_includes: {context: "Job raised exception"},
            exception:        :nil
          )
          assert_equal "BadJob", messages[2].payload[:job]["class"]
          assert_equal [], messages[2].payload[:job]["args"]
        end
      end
    end

    # Unit tests for the job logger's Sidekiq 8 configuration options.
    # These run on all Sidekiq versions since the config is passed in directly.
    describe RailsSemanticLogger::Sidekiq::JobLogger do
      let(:item) { {"jid" => "123", "class" => "SimpleJob", "queue" => "default", "priority" => "high"} }

      describe "skip_default_job_logging" do
        let(:job_logger) { RailsSemanticLogger::Sidekiq::JobLogger.new({skip_default_job_logging: true}) }

        it "suppresses perform messages but still runs the job" do
          performed = false
          messages  = semantic_logger_events do
            job_logger.call(item, "default") { performed = true }
          end

          assert performed
          assert_equal 0, messages.count, -> { messages.collect(&:to_h).ai }
        end
      end

      describe "logged_job_attributes" do
        let(:job_logger) { RailsSemanticLogger::Sidekiq::JobLogger.new({logged_job_attributes: %w[bid tags priority]}) }

        it "adds configured job attributes to the logging context" do
          messages = semantic_logger_events do
            job_logger.prepare(item) do
              # The block stands in for the job body; only the surrounding logging is asserted.
              job_logger.call(item, "default") { nil }
            end
          end

          assert_equal 2, messages.count, -> { messages.collect(&:to_h).ai }
          assert_semantic_logger_event(
            messages[0],
            message:    "Start #perform",
            named_tags: {jid: "123", class: "SimpleJob", priority: "high", queue: "default"}
          )
        end
      end
    end
  end
end
