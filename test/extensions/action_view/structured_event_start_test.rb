require_relative "../../test_helper"

# Verifies that Active Support can leave Rails' structured "render start" listener out of a render
# outside the event reporter's debug mode, on Rails 8.1 through this gem's extension, and from
# Rails 8.2 as Rails gives it.
class StructuredEventStartTest < Minitest::Test
  describe "ActionView::StructuredEventSubscriber::Start" do
    before do
      # Loads Action View, which subscribes Start, and runs the extension's on_load hook.
      require "action_view/base"
      next if defined?(::ActionView::StructuredEventSubscriber::Start)

      skip "Rails #{Rails.version} has no structured event subscribers"
    end

    def start_listeners(name)
      ActiveSupport::Notifications.notifier.all_listeners_for(name).select do |listener|
        listener.delegate.is_a?(::ActionView::StructuredEventSubscriber::Start)
      end
    end

    %w[render_template.action_view render_layout.action_view].each do |name|
      it "is silenced for #{name} outside debug mode" do
        listeners = start_listeners(name)

        assert_equal 1, listeners.size, listeners

        ActiveSupport.event_reporter.stub(:debug_mode?, false) do
          assert(listeners.all? { |listener| listener.silenced?(name) })
        end
      end

      it "listens to #{name} in debug mode" do
        listeners = start_listeners(name)

        assert_equal 1, listeners.size, listeners

        ActiveSupport.event_reporter.with_debug do
          refute(listeners.any? { |listener| listener.silenced?(name) })
        end
      end
    end
  end
end
