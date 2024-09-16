require "active_support/log_subscriber"

module RailsSemanticLogger
  module ActionView
    # Output Semantic logs from Action View.
    class LogSubscriber < ActiveSupport::LogSubscriber
      VIEWS_PATTERN = %r{^app/views/}.freeze

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
        payload[:allocations] = event.allocations if event.respond_to?(:allocations)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:  payload,
          duration: event.duration
        )
      end

      def render_partial(event)
        return unless should_log?

        payload = {
          partial: from_rails_root(event.payload[:identifier])
        }
        payload[:within]      = from_rails_root(event.payload[:layout]) if event.payload[:layout]
        payload[:cache]       = event.payload[:cache_hit] unless event.payload[:cache_hit].nil?
        payload[:allocations] = event.allocations if event.respond_to?(:allocations)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:  payload,
          duration: event.duration
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
        payload[:allocations] = event.allocations if event.respond_to?(:allocations)

        logger.measure(
          self.class.rendered_log_level,
          "Rendered",
          payload:  payload,
          duration: event.duration
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

      if (Rails::VERSION::MAJOR == 7 && Rails::VERSION::MINOR >= 1) || Rails::VERSION::MAJOR > 7
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
            @root ||= "#{Rails.root}/"
          end

          def logger
            @logger ||= SemanticLogger["ActionView"]
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
      end

      private

      @logger             = SemanticLogger["ActionView"]
      @rendered_log_level = :debug

      EMPTY = "".freeze

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
