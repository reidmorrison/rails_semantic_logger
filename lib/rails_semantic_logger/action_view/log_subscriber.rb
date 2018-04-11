require 'active_support/log_subscriber'

module RailsSemanticLogger
  module ActionView
    # Output Semantic logs from Action View.
    class LogSubscriber < ActiveSupport::LogSubscriber
      VIEWS_PATTERN = /^app\/views\//

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

        payload          = {
          template: from_rails_root(event.payload[:identifier])
        }
        payload[:within] = from_rails_root(event.payload[:layout]) if event.payload[:layout]

        logger.measure(
          self.class.rendered_log_level,
          'Rendered',
          payload:  payload,
          duration: event.duration
        )
      end

      def render_partial(event)
        return unless should_log?

        payload          = {
          partial: from_rails_root(event.payload[:identifier])
        }
        payload[:within] = from_rails_root(event.payload[:layout]) if event.payload[:layout]
        payload[:cache]  = payload[:cache_hit] unless event.payload[:cache_hit].nil?

        logger.measure(
          self.class.rendered_log_level,
          'Rendered',
          payload:  payload,
          duration: event.duration
        )
      end

      def render_collection(event)
        return unless should_log?

        identifier = event.payload[:identifier] || 'templates'

        payload              = {
          template: from_rails_root(identifier),
          count:    payload[:count]
        }
        payload[:cache_hits] = payload[:cache_hits] if payload[:cache_hits]

        logger.measure(
          self.class.rendered_log_level,
          'Rendered',
          payload:  payload,
          duration: event.duration
        )
      end

      def start(name, id, payload)
        if (name == 'render_template.action_view') && should_log?
          payload          = {template: from_rails_root(payload[:identifier])}
          payload[:within] = from_rails_root(payload[:layout]) if payload[:layout]

          logger.send(self.class.rendered_log_level, message: 'Rendering', payload:  payload)
        end

        super
      end

      private

      @logger             = SemanticLogger['ActionView']
      @rendered_log_level = :debug

      EMPTY = ''.freeze

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
