require_relative "test_helper"

class SolidQueueTest < Minitest::Test
  describe "SolidQueue" do
    before do
      skip "SolidQueue is not available" unless defined?(::SolidQueue)
    end

    let(:subscriber) { RailsSemanticLogger::SolidQueue::LogSubscriber.new }

    let(:event) do
      ActiveSupport::Notifications::Event.new(event_name, 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload)
    end

    describe "#claim" do
      let(:event_name) { "claim.solid_queue" }
      let(:payload) do
        {process_id: 42, job_ids: [1, 2, 3], claimed_job_ids: [1, 2], size: 3}
      end

      it "logs a structured debug event" do
        messages = semantic_logger_events do
          subscriber.claim(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Claim jobs",
          payload_includes: {
            process_id:      42,
            claimed_job_ids: [1, 2],
            size:            3
          }
        )
      end
    end

    describe "#release_many_claimed" do
      let(:event_name) { "release_many_claimed.solid_queue" }
      let(:payload) { {size: 5} }

      it "logs at info level" do
        messages = semantic_logger_events do
          subscriber.release_many_claimed(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          name:             "SolidQueue",
          message:          "Release claimed jobs",
          payload_includes: {size: 5}
        )
      end
    end

    describe "#fail_many_claimed" do
      let(:event_name) { "fail_many_claimed.solid_queue" }
      let(:payload) { {job_ids: [1, 2], process_ids: [10, 11]} }

      it "logs at warn level" do
        messages = semantic_logger_events do
          subscriber.fail_many_claimed(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:   :warn,
          name:    "SolidQueue",
          message: "Fail claimed jobs"
        )
      end
    end

    describe "#thread_error" do
      let(:event_name) { "thread_error.solid_queue" }
      let(:payload) { {error: ArgumentError.new("boom")} }

      it "passes the exception object through" do
        messages = semantic_logger_events do
          subscriber.thread_error(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:   :error,
          name:    "SolidQueue",
          message: "Error in thread"
        )

        exception = messages[0].exception

        assert_kind_of ArgumentError, exception
        assert_equal "boom", exception.message
      end
    end

    describe "#start_process" do
      let(:event_name) { "start_process.solid_queue" }
      let(:process_struct) { Struct.new(:pid, :hostname, :process_id, :name, :kind, :metadata) }
      let(:process) do
        process_struct.new(1234, "host.local", "abc-123", "worker-1", "Worker", {polling_interval: 0.1, queues: "default"})
      end
      let(:payload) { {process: process} }

      it "merges process metadata into the payload" do
        messages = semantic_logger_events do
          subscriber.start_process(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          name:             "SolidQueue",
          message:          "Started Worker",
          payload_includes: {
            pid:              1234,
            hostname:         "host.local",
            process_id:       "abc-123",
            name:             "worker-1",
            polling_interval: 0.1,
            queues:           "default"
          }
        )
      end
    end

    describe "#enqueue_recurring_task" do
      let(:event_name) { "enqueue_recurring_task.solid_queue" }

      describe "on success" do
        let(:payload) { {task: "my_task", active_job_id: "job-1", at: Time.zone.now} }

        it "logs a debug event" do
          messages = semantic_logger_events do
            subscriber.enqueue_recurring_task(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "SolidQueue",
            message:          "Enqueued recurring task",
            payload_includes: {task: "my_task", active_job_id: "job-1"}
          )
        end
      end

      describe "on error" do
        let(:payload) { {task: "my_task", enqueue_error: "boom"} }

        it "logs an error event" do
          messages = semantic_logger_events do
            subscriber.enqueue_recurring_task(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :error,
            name:             "SolidQueue",
            message:          "Error enqueuing recurring task",
            payload_includes: {task: "my_task", enqueue_error: "boom"}
          )
        end
      end

      describe "on another adapter" do
        let(:at) { Time.zone.now }
        let(:payload) { {task: "my_task", active_job_id: "job-1", other_adapter: true, at: at} }

        it "logs that the task was enqueued outside Solid Queue" do
          messages = semantic_logger_events do
            subscriber.enqueue_recurring_task(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "SolidQueue",
            message:          "Enqueued recurring task outside Solid Queue",
            payload_includes: {task: "my_task", active_job_id: "job-1", at: at.iso8601}
          )
        end
      end

      describe "when skipped" do
        let(:payload) { {task: "my_task", skipped: true} }

        it "logs that the task was skipped" do
          messages = semantic_logger_events do
            subscriber.enqueue_recurring_task(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "SolidQueue",
            message:          "Skipped recurring task – already dispatched",
            payload_includes: {task: "my_task"}
          )
        end
      end
    end

    describe "#dispatch_scheduled" do
      let(:event_name) { "dispatch_scheduled.solid_queue" }
      let(:payload) { {batch_size: 100, size: 7} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.dispatch_scheduled(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Dispatch scheduled jobs",
          payload_includes: {batch_size: 100, size: 7}
        )
      end
    end

    describe "#release_claimed" do
      let(:event_name) { "release_claimed.solid_queue" }
      let(:payload) { {job_id: 1, process_id: 42} }

      it "logs at info level" do
        messages = semantic_logger_events do
          subscriber.release_claimed(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          name:             "SolidQueue",
          message:          "Release claimed job",
          payload_includes: {job_id: 1, process_id: 42}
        )
      end
    end

    describe "#retry_all" do
      let(:event_name) { "retry_all.solid_queue" }
      let(:payload) { {jobs_size: 10, size: 8} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.retry_all(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Retry failed jobs",
          payload_includes: {jobs_size: 10, size: 8}
        )
      end
    end

    describe "#retry" do
      let(:event_name) { "retry.solid_queue" }
      let(:payload) { {job_id: 99} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.retry(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Retry failed job",
          payload_includes: {job_id: 99}
        )
      end
    end

    describe "#discard_all" do
      let(:event_name) { "discard_all.solid_queue" }
      let(:payload) { {jobs_size: 10, size: 8, status: "failed"} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.discard_all(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Discard jobs",
          payload_includes: {jobs_size: 10, size: 8, status: "failed"}
        )
      end
    end

    describe "#discard" do
      let(:event_name) { "discard.solid_queue" }
      let(:payload) { {job_id: 99, status: "failed"} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.discard(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Discard job",
          payload_includes: {job_id: 99, status: "failed"}
        )
      end
    end

    describe "#release_many_blocked" do
      let(:event_name) { "release_many_blocked.solid_queue" }
      let(:payload) { {limit: 50, size: 3} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.release_many_blocked(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Unblock jobs",
          payload_includes: {limit: 50, size: 3}
        )
      end
    end

    describe "#release_blocked" do
      let(:event_name) { "release_blocked.solid_queue" }
      let(:payload) { {job_id: 99, concurrency_key: "key-1", released: true} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.release_blocked(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Release blocked job",
          payload_includes: {job_id: 99, concurrency_key: "key-1", released: true}
        )
      end
    end

    describe "#shutdown_process" do
      let(:event_name) { "shutdown_process.solid_queue" }
      let(:process_struct) { Struct.new(:pid, :hostname, :process_id, :name, :kind, :metadata) }
      let(:process) do
        process_struct.new(1234, "host.local", "abc-123", "worker-1", "Worker", {polling_interval: 0.1, queues: "default"})
      end
      let(:payload) { {process: process} }

      it "merges process metadata into the payload" do
        messages = semantic_logger_events do
          subscriber.shutdown_process(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          name:             "SolidQueue",
          message:          "Shutdown Worker",
          payload_includes: {
            pid:              1234,
            hostname:         "host.local",
            process_id:       "abc-123",
            name:             "worker-1",
            polling_interval: 0.1,
            queues:           "default"
          }
        )
      end
    end

    describe "#register_process" do
      let(:event_name) { "register_process.solid_queue" }

      describe "on success" do
        let(:payload) { {kind: "Worker", pid: 1234, hostname: "host.local", process_id: "abc-123", name: "worker-1"} }

        it "logs a debug event" do
          messages = semantic_logger_events do
            subscriber.register_process(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "SolidQueue",
            message:          "Register Worker",
            payload_includes: {pid: 1234, hostname: "host.local", process_id: "abc-123", name: "worker-1"}
          )
        end
      end

      describe "on error" do
        let(:payload) do
          {kind: "Worker", pid: 1234, hostname: "host.local", process_id: "abc-123", name: "worker-1",
           error: ArgumentError.new("boom")}
        end

        it "logs a warning with the exception" do
          messages = semantic_logger_events do
            subscriber.register_process(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:     :warn,
            name:      "SolidQueue",
            message:   "Error registering Worker",
            exception: ArgumentError
          )
          assert_equal "boom", messages[0].exception.message
        end
      end
    end

    describe "#deregister_process" do
      let(:event_name) { "deregister_process.solid_queue" }
      let(:process_struct) { Struct.new(:id, :pid, :hostname, :name, :last_heartbeat_at, :kind) }
      let(:heartbeat) { Time.zone.now }
      let(:process) do
        process_struct.new(7, 1234, "host.local", "worker-1", heartbeat, "Worker")
      end

      describe "on success" do
        let(:payload) { {process: process, claimed_size: 2, pruned: false} }

        it "logs a debug event" do
          messages = semantic_logger_events do
            subscriber.deregister_process(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "SolidQueue",
            message:          "Deregister Worker",
            payload_includes: {
              process_id:        7,
              pid:               1234,
              hostname:          "host.local",
              name:              "worker-1",
              last_heartbeat_at: heartbeat.iso8601,
              claimed_size:      2,
              pruned:            false
            }
          )
        end
      end

      describe "on error" do
        let(:payload) { {process: process, claimed_size: 2, pruned: false, error: ArgumentError.new("boom")} }

        it "logs a warning with the exception" do
          messages = semantic_logger_events do
            subscriber.deregister_process(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:     :warn,
            name:      "SolidQueue",
            message:   "Error deregistering Worker",
            exception: ArgumentError
          )
          assert_equal "boom", messages[0].exception.message
        end
      end
    end

    describe "#prune_processes" do
      let(:event_name) { "prune_processes.solid_queue" }
      let(:payload) { {size: 3} }

      it "logs a debug event" do
        messages = semantic_logger_events do
          subscriber.prune_processes(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "SolidQueue",
          message:          "Prune dead processes",
          payload_includes: {size: 3}
        )
      end
    end

    describe "#graceful_termination" do
      let(:event_name) { "graceful_termination.solid_queue" }

      describe "when it completes in time" do
        let(:payload) { {process_id: "abc-123", supervisor_pid: 1234, supervised_processes: [1, 2]} }

        it "logs at info level" do
          messages = semantic_logger_events do
            subscriber.graceful_termination(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :info,
            name:             "SolidQueue",
            message:          "Supervisor terminated gracefully",
            payload_includes: {process_id: "abc-123", supervisor_pid: 1234, supervised_processes: [1, 2]}
          )
        end
      end

      describe "when the shutdown timeout is exceeded" do
        let(:payload) do
          {process_id: "abc-123", supervisor_pid: 1234, supervised_processes: [1, 2], shutdown_timeout_exceeded: true}
        end

        it "logs at warn level" do
          messages = semantic_logger_events do
            subscriber.graceful_termination(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :warn,
            name:             "SolidQueue",
            message:          "Supervisor wasn't terminated gracefully - shutdown timeout exceeded",
            payload_includes: {process_id: "abc-123", supervisor_pid: 1234}
          )
        end
      end
    end

    describe "#immediate_termination" do
      let(:event_name) { "immediate_termination.solid_queue" }
      let(:payload) { {process_id: "abc-123", supervisor_pid: 1234, supervised_processes: [1, 2]} }

      it "logs at info level" do
        messages = semantic_logger_events do
          subscriber.immediate_termination(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :info,
          name:             "SolidQueue",
          message:          "Supervisor terminated immediately",
          payload_includes: {process_id: "abc-123", supervisor_pid: 1234, supervised_processes: [1, 2]}
        )
      end
    end

    describe "#unhandled_signal_error" do
      let(:event_name) { "unhandled_signal_error.solid_queue" }
      let(:payload) { {signal: "SIGKILL"} }

      it "logs at error level" do
        messages = semantic_logger_events do
          subscriber.unhandled_signal_error(event)
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :error,
          name:             "SolidQueue",
          message:          "Received unhandled signal",
          payload_includes: {signal: "SIGKILL"}
        )
      end
    end

    describe "#replace_fork" do
      let(:event_name) { "replace_fork.solid_queue" }
      let(:status_struct) do
        Struct.new(:exitstatus, :pid, :signaled, :stopsig, :termsig) do
          def signaled?
            signaled
          end
        end
      end
      let(:status) { status_struct.new(0, 4321, false, nil, nil) }

      describe "when the terminated fork is known" do
        let(:fork_struct) { Struct.new(:kind, :hostname, :name) }
        let(:fork) { fork_struct.new("Worker", "host.local", "worker-1") }
        let(:payload) { {supervisor_pid: 1234, status: status, pid: 4321, fork: fork} }

        it "logs at info level with the fork details" do
          messages = semantic_logger_events do
            subscriber.replace_fork(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :info,
            name:             "SolidQueue",
            message:          "Replaced terminated Worker",
            payload_includes: {
              pid:             4321,
              status:          0,
              pid_from_status: 4321,
              signaled:        false,
              hostname:        "host.local",
              name:            "worker-1"
            }
          )
        end
      end

      describe "when the fork had already died" do
        let(:payload) { {supervisor_pid: 1234, status: status, pid: 4321, fork: nil} }

        it "logs a warning" do
          messages = semantic_logger_events do
            subscriber.replace_fork(event)
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :warn,
            name:             "SolidQueue",
            message:          "Tried to replace forked process but it had already died",
            payload_includes: {pid: 4321, status: 0, pid_from_status: 4321}
          )
        end
      end

      describe "when reparented under Docker (supervisor pid 1)" do
        let(:payload) { {supervisor_pid: 1, status: status, pid: 4321, fork: nil} }

        it "does not log anything" do
          messages = semantic_logger_events do
            subscriber.replace_fork(event)
          end

          assert_equal 0, messages.count, messages
        end
      end
    end
  end
end
