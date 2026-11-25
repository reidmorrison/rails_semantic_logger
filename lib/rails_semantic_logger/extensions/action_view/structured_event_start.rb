# Lets Active Support leave Rails 8.1's structured "render start" listener out of a render.
#
# On Rails 8.1, ActionView::StructuredEventSubscriber::Start reports the start of each template and
# layout render to the event reporter, which drops it outside debug mode. It answers no `silenced?`,
# so Active Support instruments every template and layout render for it, even when nothing else
# would. Rails 8.2 gives it this `silenced?`; this gives it the same on 8.1, and does nothing where
# Start already has one, or does not exist (Rails 7.2 and 8.0).
#
# Active Support asks a listener whether it can be silenced once, as it subscribes, and Rails 8.1
# subscribes Start as it loads ActionView::Base, so its listeners are subscribed again once Start
# answers. Remove this file with support for Rails 8.1.
ActiveSupport.on_load(:action_view, run_once: true) do
  next unless defined?(ActionView::StructuredEventSubscriber::Start)

  start = ActionView::StructuredEventSubscriber::Start
  next if start.method_defined?(:silenced?)

  start.define_method(:silenced?) { |_name| !ActiveSupport.event_reporter.debug_mode? }

  %w[render_template.action_view render_layout.action_view].each do |name|
    ActiveSupport::Notifications.notifier.all_listeners_for(name).each do |listener|
      next unless listener.delegate.is_a?(start)

      # Subscribed again before it is unsubscribed, so that the event never has no Start listener.
      ActiveSupport::Notifications.subscribe(name, listener.delegate)
      ActiveSupport::Notifications.unsubscribe(listener)
    end
  end
end
