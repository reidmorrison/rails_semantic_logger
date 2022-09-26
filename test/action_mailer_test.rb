require_relative "test_helper"

class ActionMailerTest < Minitest::Test
  class MyMailer < ActionMailer::Base
    def some_email(to:, from:, subject:)
      mail(to: to, from: from, subject: subject, body: "Hello")
    end
  end

  describe "ActionMailer" do
    before do
      ::ActionMailer::Base.delivery_method = :test
      @mock_logger = MockLogger.new
      @appender    = SemanticLogger.add_appender(logger: @mock_logger, formatter: :raw)
    end

    after do
      SemanticLogger.remove_appender(@appender)
    end

    describe "#deliver" do
      it "sets the ActionMailer logger" do
        assert_kind_of SemanticLogger::Logger, MyMailer.logger
      end

      it "sends the email" do
        MyMailer.some_email(to: 'test@test.com', from: 'test@test.com', subject: 'test').deliver_now
      end
    end

    describe "Logging::LogSubscriber" do
      before do
        skip "Older rails does not support ActiveSupport::Notification" unless defined?(ActiveSupport::Notifications)
      end

      let(:subscriber) { RailsSemanticLogger::ActionMailer::LogSubscriber.new }

      let(:event) do
        ActiveSupport::Notifications::Event.new event_name,
                                                5.seconds.ago,
                                                Time.zone.now,
                                                SecureRandom.uuid,
                                                payload
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
