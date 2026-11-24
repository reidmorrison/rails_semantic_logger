module RailsSemanticLogger
  module Metrics
    # Records how long Action View takes to render, as `rails.action_view.render.duration`, since no
    # OpenTelemetry convention covers template rendering. Each render is recorded whatever level its
    # log entry is logged at.
    class ActionView < Subscriber
      NAME = "rails.action_view.render.duration".freeze

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

      # The template's path from the application's views, such as "articles/show.html.erb", or from
      # its root for a template elsewhere, such as a gem's. The templates of an application are a
      # fixed set, so the number of series stays bounded.
      def template(identifier)
        return unless identifier

        identifier.delete_prefix(rails_root).delete_prefix("app/views/")
      end

      def rails_root
        @rails_root ||= "#{::Rails.root}/"
      end
    end
  end
end
