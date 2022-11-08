require_relative "test_helper"

class ActionMailerTest < Minitest::Test
  class MyMailer < ActionMailer::Base
    def some_email(to:, from:, subject:)
      mail(to: to, from: from, subject: subject, body: "Hello")
    end
  end

  describe "ActionMailer" do
    describe "#deliver" do
      it "sets the ActionMailer logger" do
        assert_kind_of SemanticLogger::Logger, MyMailer.logger
      end

      it "sends the email" do
        MyMailer.some_email(to: 'test@test.com', from: 'test@test.com', subject: 'test').deliver_now
      end

      it "writes log messages" do
        messages = semantic_logger_events do
          MyMailer.some_email(to: 'test@test.com', from: 'test@test.com', subject: 'test').deliver_now
        end
        assert_equal 2, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level: :info,
          name: "ActionMailer::Base",
          message_includes: "ActionMailerTest::MyMailer#some_email: processed outbound mail",
          payload_includes: {
            event_name: "process.action_mailer",
            mailer: "ActionMailerTest::MyMailer",
            action: :some_email,
          }
        )

        assert_semantic_logger_event(
          messages[1],
          level: :info,
          name: "ActionMailer::Base",
          message_includes: Rails::VERSION::MAJOR >= 6 ? "Delivered mail" : "Skipped delivery",
          payload_includes: {
            event_name: "deliver.action_mailer",
            mailer: "ActionMailerTest::MyMailer",
            perform_deliveries: Rails::VERSION::MAJOR >= 6 ? true : nil,
            subject: "test",
            to: ["test@test.com"],
            from: ["test@test.com"],
          }
        )
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
          mailer: 'MyMailer',
          action: :some_email,
        }
      end

      let(:event_name) { "deliver.action_mailer" }

      let(:mailer) do
        MyMailer.some_email(to: 'test@test.com', from: 'test@test.com', subject: 'test')
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
            assert_equal(formatter.payload[:event_name], "deliver.action_mailer")
            assert_equal(formatter.payload[:mailer], "MyMailer")
            assert_equal(formatter.payload[:action], :some_email)
            assert_kind_of(Float, formatter.payload[:duration])
          end
        end
      end
    end
  end
end
