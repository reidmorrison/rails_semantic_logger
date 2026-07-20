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
      VIEWS_PATTERN = %r{^app/views/}

      class << self
        attr_reader :logger
        attr_accessor :rendered_log_level
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
          payload:  payload,
          duration: event.duration,
          metric:   "rails.view.render.template"
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
          payload:  payload,
          duration: event.duration,
          metric:   "rails.view.render.partial"
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
          payload:  payload,
          duration: event.duration,
          metric:   "rails.view.render.layout"
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
          payload:  payload,
          duration: event.duration,
          metric:   "rails.view.render.collection"
        )
      end

      def start(name, id, payload)
        if ["render_template.action_view", "render_layout.action_view"].include?(name) && should_log?
          qualifier        = " layout" if name == "render_layout.action_view"
          payload          = {template: from_rails_root(payload[:identifier])}
          payload[:within] = from_rails_root(payload[:layout]) if payload[:layout]

          logger.send(self.class.rendered_log_level, message: "Rendering#{qualifier}", payload: payload)
        end

        super
      end

      class Start
        def start(name, _id, payload)
          return unless %w[render_template.action_view render_layout.action_view].include?(name)

          qualifier        = " layout" if name == "render_layout.action_view"
          payload          = {template: from_rails_root(payload[:identifier])}
          payload[:within] = from_rails_root(payload[:layout]) if payload[:layout]

          logger.debug(message: "Rendering#{qualifier}", payload: payload)
        end

        def finish(name, id, payload)
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
      end

      def self.attach_to(*)
        ActiveSupport::Notifications.unsubscribe("render_template.action_view")
        ActiveSupport::Notifications.unsubscribe("render_layout.action_view")
        ActiveSupport::Notifications.subscribe("render_template.action_view",
                                               RailsSemanticLogger::ActionView::LogSubscriber::Start.new)
        ActiveSupport::Notifications.subscribe("render_layout.action_view",
                                               RailsSemanticLogger::ActionView::LogSubscriber::Start.new)

        super
      end

      EMPTY = "".freeze

      @logger             = ::ActionView::Base.logger
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
    end
  end
end
