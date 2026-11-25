require_relative "test_helper"

# Verifies that each log subscriber lets Active Support leave it out of an event that it would not
# log, and only then, so that, as with Rails' own log subscribers, an event below the log level is
# not built for it.
class SilencedBelowLevelTest < Minitest::Test
  describe RailsSemanticLogger::SilencedBelowLevel do
    # Runs the block with the logger at the level, then gives the logger back the level it had,
    # including none, which follows the default level.
    def at_level(logger, level)
      previous     = logger.instance_variable_get(:@level)
      logger.level = level
      yield
    ensure
      logger.level = previous
    end

    def subscriber(klass)
      klass.new
    end

    let(:subscriber_class) do
      Class.new do
        include RailsSemanticLogger::SilencedBelowLevel

        attr_accessor :logger

        def log_level_of(name)
          {"known.test" => :warn}[name]
        end
      end
    end

    it "is silenced while its logger does not log at the event's level" do
      silenceable        = subscriber_class.new
      silenceable.logger = SemanticLogger::Logger.new("SilencedBelowLevelTest")

      at_level(silenceable.logger, :error) { assert silenceable.silenced?("known.test") }
      at_level(silenceable.logger, :warn) { refute silenceable.silenced?("known.test") }
    end

    it "is silenced without a logger" do
      assert subscriber_class.new.silenced?("known.test")
    end

    it "listens when its logger cannot tell whether it logs at the level" do
      silenceable        = subscriber_class.new
      silenceable.logger = Object.new

      refute silenceable.silenced?("known.test")
    end

    it "is never silenced for an event that it gives no level for" do
      silenceable        = subscriber_class.new
      silenceable.logger = SemanticLogger::Logger.new("SilencedBelowLevelTest")

      at_level(silenceable.logger, :fatal) { refute silenceable.silenced?("other.test") }
    end

    describe RailsSemanticLogger::ActiveRecord::LogSubscriber do
      it "is silenced for queries below :debug" do
        sub = subscriber(RailsSemanticLogger::ActiveRecord::LogSubscriber)

        at_level(::ActiveRecord::Base.logger, :info) { assert sub.silenced?("sql.active_record") }
        at_level(::ActiveRecord::Base.logger, :debug) { refute sub.silenced?("sql.active_record") }
      end
    end

    describe RailsSemanticLogger::ActionMailer::LogSubscriber do
      it "is silenced for deliveries below :debug" do
        sub = subscriber(RailsSemanticLogger::ActionMailer::LogSubscriber)

        at_level(::ActionMailer::Base.logger, :info) { assert sub.silenced?("deliver.action_mailer") }
        at_level(::ActionMailer::Base.logger, :debug) { refute sub.silenced?("deliver.action_mailer") }
      end
    end

    describe RailsSemanticLogger::ActiveJob::LogSubscriber do
      it "listens to a job's perform while it would log a job that failed" do
        sub = subscriber(RailsSemanticLogger::ActiveJob::LogSubscriber)

        at_level(::ActiveJob::Base.logger, :warn) do
          refute sub.silenced?("perform.active_job")
          assert sub.silenced?("perform_start.active_job")
        end
        at_level(::ActiveJob::Base.logger, :fatal) { assert sub.silenced?("perform.active_job") }
      end

      it "gives a level for every event that it logs" do
        assert_equal handled_events(RailsSemanticLogger::ActiveJob::LogSubscriber, "active_job"),
                     RailsSemanticLogger::ActiveJob::LogSubscriber::LOG_LEVELS.keys.sort
      end

      it "gives only levels that a logger can be asked about" do
        assert_empty RailsSemanticLogger::ActiveJob::LogSubscriber::LOG_LEVELS.values -
                     RailsSemanticLogger::SilencedBelowLevel::PREDICATES.keys
      end
    end

    describe RailsSemanticLogger::SolidQueue::LogSubscriber do
      it "listens to an event while it would log its warning" do
        sub    = subscriber(RailsSemanticLogger::SolidQueue::LogSubscriber)
        logger = SemanticLogger[::SolidQueue]

        sub.stub(:logger, logger) do
          at_level(logger, :warn) do
            refute sub.silenced?("register_process.solid_queue")
            assert sub.silenced?("claim.solid_queue")
          end
        end
      end

      it "gives a level for every event that it logs" do
        assert_equal handled_events(RailsSemanticLogger::SolidQueue::LogSubscriber, "solid_queue"),
                     RailsSemanticLogger::SolidQueue::LogSubscriber::LOG_LEVELS.keys.sort
      end

      it "gives only levels that a logger can be asked about" do
        assert_empty RailsSemanticLogger::SolidQueue::LogSubscriber::LOG_LEVELS.values -
                     RailsSemanticLogger::SilencedBelowLevel::PREDICATES.keys
      end
    end

    describe RailsSemanticLogger::ActionView::LogSubscriber do
      it "is silenced for renders below the rendered level, as it is set now" do
        sub      = subscriber(RailsSemanticLogger::ActionView::LogSubscriber)
        rendered = RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level

        at_level(::ActionView::Base.logger, :info) do
          assert sub.silenced?("render_partial.action_view")

          RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = :info

          refute sub.silenced?("render_partial.action_view")
        end
      ensure
        RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = rendered
      end

      it "leaves Action View's own render listeners silenced below the rendered level" do
        notifier = ActiveSupport::Notifications.notifier
        ours     = notifier.all_listeners_for("render_partial.action_view").select do |listener|
          listener.delegate.is_a?(RailsSemanticLogger::ActionView::LogSubscriber)
        end

        refute_empty ours
        at_level(::ActionView::Base.logger, :info) do
          assert(ours.all? { |listener| listener.silenced?("render_partial.action_view") })
        end
      end
    end

    describe RailsSemanticLogger::ActionView::LogSubscriber::Start do
      let(:start) { RailsSemanticLogger::ActionView::LogSubscriber::Start.new }

      # Runs the block with the rendered level at the level, then sets it back.
      def at_rendered_level(level)
        rendered = RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level
        RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = level
        yield
      ensure
        RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level = rendered
      end

      it "is silenced while Action View does not log at the rendered level" do
        at_rendered_level(:debug) do
          at_level(::ActionView::Base.logger, :info) { assert start.silenced?("render_template.action_view") }
          at_level(::ActionView::Base.logger, :debug) { refute start.silenced?("render_template.action_view") }
        end
      end

      it "is silenced without an Action View logger" do
        ::ActionView::Base.stub(:logger, nil) { assert start.silenced?("render_template.action_view") }
      end

      it "follows the rendered level, as it is set now" do
        at_rendered_level(:info) do
          at_level(::ActionView::Base.logger, :info) { refute start.silenced?("render_template.action_view") }
          at_level(::ActionView::Base.logger, :warn) { assert start.silenced?("render_template.action_view") }
        end
      end

      it "is given only a level that Semantic Logger knows, as a symbol" do
        assert_raises(ArgumentError) { at_rendered_level(:inf) { nil } }
        assert_raises(ArgumentError) { at_rendered_level(nil) { nil } }
        at_rendered_level("info") do
          assert_equal :info, RailsSemanticLogger::ActionView::LogSubscriber.rendered_log_level
        end
      end

      it "listens when Action View's logger cannot tell whether it logs at the rendered level" do
        ::ActionView::Base.stub(:logger, Object.new) { refute start.silenced?("render_template.action_view") }
      end
    end

    # The events that the subscriber's handlers log: its public methods, other than those of its class
    # attributes, as ActiveSupport::Subscriber attaches them.
    def handled_events(klass, namespace)
      methods = klass.public_instance_methods(false).map(&:to_s).grep(/\A[a-z_]+\z/)
      (methods - %w[backtrace_cleaner]).map { |method| "#{method}.#{namespace}" }.sort
    end
  end
end
