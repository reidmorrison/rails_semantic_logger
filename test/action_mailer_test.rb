require_relative "test_helper"

class ActionMailerTest < Minitest::Test
  class MyMailer < ActionMailer::Base
    def some_email(opts)
      mail(to: opts[:to], from: opts[:from], subject: opts[:subject], body: "Hello")
    end
  end

  describe "ActionMailer" do
    describe "#deliver" do
      it "sets the ActionMailer logger" do
        assert_kind_of SemanticLogger::Logger, MyMailer.logger
      end

      it "sends the email" do
        MyMailer.some_email(to: "test@test.com", from: "test@test.com", subject: "test").deliver_now
      end

      it "writes log messages" do
        messages = semantic_logger_events do
          MyMailer.some_email(to: "test@test.com", from: "test@test.com", subject: "test").deliver_now
        end

        assert_equal 2, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActionMailer::Base",
          message_includes: "ActionMailerTest::MyMailer#some_email: processed outbound mail",
          payload_includes: {
            event_name: "process.action_mailer",
            mailer:     "ActionMailerTest::MyMailer",
            action:     :some_email
          }
        )

        assert_semantic_logger_event(
          messages[1],
          level:            :info,
          name:             "ActionMailer::Base",
          message_includes: Rails::VERSION::MAJOR >= 6 ? "Delivered mail" : "Skipped delivery",
          payload_includes: {
            event_name:         "deliver.action_mailer",
            mailer:             "ActionMailerTest::MyMailer",
            perform_deliveries: Rails::VERSION::MAJOR >= 6 ? true : nil,
            subject:            "test",
            to:                 ["test@test.com"],
            from:               ["test@test.com"]
          }
        )
      end
    end

    describe "log-level gating and branches" do
      let(:subscriber) { RailsSemanticLogger::ActionMailer::LogSubscriber.new }

      def deliver_event(payload)
        ActiveSupport::Notifications::Event.new(
          "deliver.action_mailer", 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload
        )
      end

      def process_event(payload)
        ActiveSupport::Notifications::Event.new(
          "process.action_mailer", 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload
        )
      end

      describe "#deliver" do
        it "logs delivered mail at info level" do
          event = deliver_event(message_id: "<abc@mail>", perform_deliveries: true)

          events = semantic_logger_events(klass: ActionMailer::Base) { subscriber.deliver(event) }

          assert_equal 1, events.count, events
          assert_semantic_logger_event(
            events.first,
            level:            :info,
            message_includes: "Delivered mail <abc@mail>"
          )
        end

        it "logs skipped delivery when perform_deliveries is false" do
          event = deliver_event(message_id: "<abc@mail>", perform_deliveries: false)

          events = semantic_logger_events(klass: ActionMailer::Base) { subscriber.deliver(event) }

          assert_equal 1, events.count, events
          assert_semantic_logger_event(
            events.first,
            level:            :info,
            message_includes: "Skipped delivery of mail <abc@mail>"
          )
        end

        it "logs an error when delivery raises" do
          exception = StandardError.new("boom")
          event     = deliver_event(message_id: "<abc@mail>", exception_object: exception)

          events = semantic_logger_events(klass: ActionMailer::Base) { subscriber.deliver(event) }

          assert_equal 1, events.count, events
          assert_semantic_logger_event(
            events.first,
            level:            :error,
            message_includes: "Error delivering mail <abc@mail>",
            exception:        exception
          )
        end

        it "includes the encoded mail in the payload" do
          encoded = "To: test@test.com\r\nSubject: test\r\n\r\nHello"
          event   = deliver_event(message_id: "<abc@mail>", perform_deliveries: true, mail: encoded)

          events = semantic_logger_events(klass: ActionMailer::Base) { subscriber.deliver(event) }

          assert_equal encoded, events.first.payload[:mail]
        end

        it "is silenced when the logger level is above debug" do
          logger = SemanticLogger::Test::CaptureLogEvents.new(level: :info)
          event  = deliver_event(message_id: "<abc@mail>", perform_deliveries: true)

          ActionMailer::Base.stub(:logger, logger) { subscriber.deliver(event) }

          assert_empty logger.events
        end
      end

      describe "#process" do
        it "logs processed outbound mail at debug level" do
          event = process_event(mailer: "MyMailer", action: :some_email)

          events = semantic_logger_events(klass: ActionMailer::Base) { subscriber.process(event) }

          assert_equal 1, events.count, events
          assert_semantic_logger_event(
            events.first,
            level:            :debug,
            message_includes: "MyMailer#some_email: processed outbound mail"
          )
        end

        it "is silenced when the logger level is above debug" do
          logger = SemanticLogger::Test::CaptureLogEvents.new(level: :info)
          event  = process_event(mailer: "MyMailer", action: :some_email)

          ActionMailer::Base.stub(:logger, logger) { subscriber.process(event) }

          assert_empty logger.events
        end
      end
    end

    describe "Logging::LogSubscriber" do
      before do
        skip "Older rails does not support ActiveSupport::Notification" unless defined?(ActiveSupport::Notifications)
      end

      let(:subscriber) { RailsSemanticLogger::ActionMailer::LogSubscriber.new }

      let(:event) do
        ActiveSupport::Notifications::Event.new(event_name, 5.seconds.ago, Time.zone.now, SecureRandom.uuid, payload)
      end

      let(:payload) do
        {
          mailer: "MyMailer",
          action: :some_email
        }
      end

      let(:event_name) { "deliver.action_mailer" }

      let(:mailer) do
        MyMailer.some_email(to: "test@test.com", from: "test@test.com", subject: "test")
      end

      %i[deliver process].each do |method|
        describe "##{method}" do
          specify do
            assert ActionMailer::Base.logger.info
            subscriber.public_send(method, event)
          end
        end
      end

      describe "ActiveJob::Logging::LogSubscriber::EventFormatter" do
        let(:formatter) do
          RailsSemanticLogger::ActionMailer::LogSubscriber::EventFormatter.new(event: event, log_duration: true)
        end

        let(:event_name) { "deliver.action_mailer" }

        describe "#payload" do
          specify do
            assert_equal("deliver.action_mailer", formatter.payload[:event_name])
            assert_equal("MyMailer", formatter.payload[:mailer])
            assert_equal(:some_email, formatter.payload[:action])
            assert_kind_of(Float, formatter.payload[:duration])
          end
        end

        describe "date" do
          it "is nil when the payload has no date" do
            assert_nil formatter.payload[:date]
          end

          describe "with a time-like date" do
            let(:payload) { {mailer: "MyMailer", date: Time.utc(2026, 6, 25, 12, 0, 0)} }

            it "is converted to a UTC time" do
              assert_equal Time.utc(2026, 6, 25, 12, 0, 0), formatter.payload[:date]
              assert_equal "UTC", formatter.payload[:date].zone
            end
          end
        end

        describe "args" do
          describe "when there are no args" do
            let(:payload) { {mailer: "MyMailer"} }

            it "is nil" do
              assert_nil formatter.payload[:args]
            end
          end

          describe "with nested args" do
            let(:payload) { {mailer: "MyMailer", args: [{"a" => 1, "b" => [2, 3]}]} }

            it "is JSON with the structure preserved" do
              assert_equal [{"a" => 1, "b" => [2, 3]}], JSON.parse(formatter.payload[:args])
            end
          end

          describe "with a GlobalID record" do
            let(:record) do
              Sample.new.tap { |s| s.id = 99 }
            end
            let(:payload) { {mailer: "MyMailer", args: [record]} }

            it "converts the record to a global id" do
              assert_equal ["gid://dummy/Sample/99"], JSON.parse(formatter.payload[:args])
            end
          end

          describe "with a record that cannot be converted to a global id" do
            let(:record) { Sample.new }
            let(:payload) { {mailer: "MyMailer", args: [record]} }

            it "falls back to the argument itself" do
              # Sample.new has no id, so to_global_id raises and the record is returned as-is
              # rather than being converted to a "gid://" string.
              parsed = JSON.parse(formatter.payload[:args]).first

              assert_includes parsed.to_s, "Sample"
              refute_includes parsed.to_s, "gid://"
            end
          end
        end
      end
    end
  end
end
