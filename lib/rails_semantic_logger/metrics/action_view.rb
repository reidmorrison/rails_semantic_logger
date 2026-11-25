module RailsSemanticLogger
  module Metrics
    # Records how long Action View takes to render, as `rails.action_view.render.duration`, since no
    # OpenTelemetry convention covers template rendering. Each render is recorded whatever level its
    # log entry is logged at.
    class ActionView < Subscriber
      # The logger of Action View, whose name is the meter of its metrics.
      LOGGER_NAME = "ActionView::Base".freeze

      NAME = "rails.action_view.render.duration".freeze

      # The directory that holds the templates, of the application, a gem, or an engine.
      VIEWS = "app/views/".freeze

      def render_template(event)
        render("template", event)
      end

      def render_partial(event)
        render("partial", event)
      end

      def render_layout(event)
        render("layout", event)
      end

      def render_collection(event)
        render("collection", event)
      end

      private

      def render(kind, event)
        dimensions = {"rails.action_view.render.kind" => kind}
        template   = template(event.payload[:identifier])
        dimensions["rails.action_view.template"] = template if template
        time(NAME, event, dimensions)
      end

      # The template's path from its views directory, such as "articles/show.html.erb", for the
      # application's templates and a gem's or an engine's alike, so that the number of series stays
      # bounded and no host's directories are sent. Nil for a template outside any app/views.
      def template(identifier)
        return unless identifier

        path = identifier.delete_prefix(rails_root)
        return path.delete_prefix(VIEWS) if path.start_with?(VIEWS)

        index = path.index("/#{VIEWS}")
        path[(index + VIEWS.length + 1)..] if index
      end

      def rails_root
        @rails_root ||= "#{::Rails.root}/"
      end
    end
  end
end
