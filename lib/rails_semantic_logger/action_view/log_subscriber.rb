require "active_support/log_subscriber"

# This subscriber is a reimplementation of Rails' own ActionView::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/actionview/lib/action_view/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/actionview/lib/action_view/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/actionview/lib/action_view/log_subscriber.rb
#
# As of these versions the upstream subscriber is identical across 7.2, 8.0, and 8.1, so no
# version-specific behavior is required here.
#
module RailsSemanticLogger
  module ActionView
    # Output Semantic logs from Action View.
    class LogSubscriber < ActiveSupport::LogSubscriber
      include RailsSemanticLogger::SilencedBelowLevel

      VIEWS_PATTERN = %r{^app/views/}

      # The application's, to find the application code that rendered a template: the action, or
      # the template that rendered a partial.
      class_attribute :backtrace_cleaner, default: ::Rails.backtrace_cleaner

      class << self
        attr_accessor :rendered_log_level

        # Looked up on first use rather than when this file loads: referencing ActionView::Base
        # loads it, and Rails 8.2+ reports that when it happens before the application has
        # initialized.
        def logger
          @logger ||= ::ActionView::Base.logger
        end

        # Returns the call site of a render entry that the logger logs at the level, or nil when it
        # records none: the application code that rendered the template, such as the action that
        # called render, or the template that rendered a partial. False when there is none, as for a
        # template that Rails renders once the action has returned, even inside an around_action, so
        # that the entry records no call site rather than Active Support's frame (see ApplicationFrame).
        def call_site(logger, level)
          return unless RailsSemanticLogger.call_site?(logger, level)

          RailsSemanticLogger::ApplicationFrame.on_stack(backtrace_cleaner).call_site || false
        end
      end

      def initialize
        @rails_root = nil
        super
      end

      def render_template(event)
        return unless should_log?

        payload = {
          template: from_rails_root(event.payload[:identifier])
        }
        payload[:within]      = from_rails_root(event.payload[:layout]) if event.payload[:layout]
        payload[:allocations] = event.allocations
        payload[:gc_time]     = event.gc_time.round(2) if event.respond_to?(:gc_time)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:   payload,
          duration:  event.duration,
          call_site: call_site
        )
      end

      def render_partial(event)
        return unless should_log?

        payload = {
          partial: from_rails_root(event.payload[:identifier])
        }
        payload[:within]      = from_rails_root(event.payload[:layout]) if event.payload[:layout]
        payload[:cache]       = event.payload[:cache_hit] unless event.payload[:cache_hit].nil?
        payload[:allocations] = event.allocations
        payload[:gc_time]     = event.gc_time.round(2) if event.respond_to?(:gc_time)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:   payload,
          duration:  event.duration,
          call_site: call_site
        )
      end

      def render_layout(event)
        return unless should_log?

        payload = {
          template: from_rails_root(event.payload[:identifier])
        }
        payload[:allocations] = event.allocations
        payload[:gc_time]     = event.gc_time.round(2) if event.respond_to?(:gc_time)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered layout",
          payload:   payload,
          duration:  event.duration,
          call_site: call_site
        )
      end

      def render_collection(event)
        return unless should_log?

        identifier = event.payload[:identifier] || "templates"

        payload = {
          template: from_rails_root(identifier),
          count:    event.payload[:count]
        }
        payload[:cache_hits]  = event.payload[:cache_hits] if event.payload[:cache_hits]
        payload[:allocations] = event.allocations
        payload[:gc_time]     = event.gc_time.round(2) if event.respond_to?(:gc_time)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:   payload,
          duration:  event.duration,
          call_site: call_site
        )
      end

      def start(name, id, payload)
        if ["render_template.action_view", "render_layout.action_view"].include?(name) && should_log?
          qualifier        = " layout" if name == "render_layout.action_view"
          payload          = {template: from_rails_root(payload[:identifier])}
          payload[:within] = from_rails_root(payload[:layout]) if payload[:layout]

          logger.send(self.class.rendered_log_level, message: "Rendering#{qualifier}", payload: payload,
                                                     call_site: call_site)
        end

        super
      end

      class Start
        def start(name, _id, payload)
          return unless %w[render_template.action_view render_layout.action_view].include?(name)

          qualifier        = " layout" if name == "render_layout.action_view"
          payload          = {template: from_rails_root(payload[:identifier])}
          payload[:within] = from_rails_root(payload[:layout]) if payload[:layout]

          logger.debug(message: "Rendering#{qualifier}", payload: payload, call_site: call_site)
        end

        def finish(name, id, payload)
        end

        # Whether Active Support may leave it out of the render events: while Action View logs nothing
        # at :debug, the level of its "Rendering" entries. Asked each time an event starts, so that a
        # render below the log level builds no event when its other listeners are silenced too, as in
        # Rails' own Start. Never raises, as it is asked from the code that renders: when the answer is
        # not known, it listens.
        def silenced?(_name)
          logger.nil? || !logger.debug?
        rescue StandardError
          false
        end

        private

        def from_rails_root(string)
          string = string.sub(rails_root, "")
          string.sub!(VIEWS_PATTERN, "")
          string
        end

        def rails_root
          @rails_root ||= "#{Rails.root}/"
        end

        def logger
          @logger ||= ::ActionView::Base.logger
        end

        def call_site
          LogSubscriber.call_site(logger, :debug)
        end
      end

      def self.attach_to(*)
        %w[render_template.action_view render_layout.action_view].each do |name|
          detach_start_listeners(name)
          ActiveSupport::Notifications.subscribe(name, RailsSemanticLogger::ActionView::LogSubscriber::Start.new)
        end

        super
      end

      # Detaches the listeners that log "Rendering" when a render starts, Rails' own and any this
      # subscriber attached before, and no other: the render events also reach the metrics, Rails'
      # structured event subscriber, and any the application or another gem attached.
      def self.detach_start_listeners(name)
        ActiveSupport::Notifications.notifier.all_listeners_for(name).each do |listener|
          next unless start_listener?(listener.instance_variable_get(:@delegate))

          ActiveSupport::Notifications.unsubscribe(listener)
        end
      end

      def self.start_listener?(delegate)
        delegate.is_a?(RailsSemanticLogger::ActionView::LogSubscriber::Start) ||
          (defined?(::ActionView::LogSubscriber::Start) && delegate.is_a?(::ActionView::LogSubscriber::Start))
      end

      private_class_method :detach_start_listeners, :start_listener?

      EMPTY = "".freeze

      @rendered_log_level = :debug

      private

      def should_log?
        logger.send("#{self.class.rendered_log_level}?")
      end

      def from_rails_root(string)
        string = string.sub(rails_root, EMPTY)
        string.sub!(VIEWS_PATTERN, EMPTY)
        string
      end

      def rails_root
        @rails_root ||= "#{Rails.root}/"
      end

      def logger
        self.class.logger
      end

      # Every render is logged at the rendered level, which the application can change at any time.
      # The "Rendering" entries are Start's, which answers for itself.
      def log_level_of(_name)
        self.class.rendered_log_level
      end

      def call_site
        self.class.call_site(logger, self.class.rendered_log_level)
      end
    end
  end
end
