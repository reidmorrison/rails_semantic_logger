require_relative "../test_helper"

module Metrics
  class ActionViewTest < ActionDispatch::IntegrationTest
    describe RailsSemanticLogger::Metrics::ActionView do
      # Emits the notification that the subscriber listens to, as Action View does when it renders.
      def instrument(name, payload)
        semantic_logger_metrics do
          ActiveSupport::Notifications.instrument("#{name}.action_view", payload) { :rendered }
        end
      end

      %w[template partial layout].each do |kind|
        it "records the duration of rendering a #{kind} by its path from the views" do
          metrics = instrument("render_#{kind}", identifier: "#{Rails.root}/app/views/articles/_form.html.erb")

          assert_metric(
            metrics,
            name:       "rails.action_view.render.duration",
            kind:       :histogram,
            unit:       "s",
            dimensions: {"rails.action_view.render.kind" => kind,
                         "rails.action_view.template"    => "articles/_form.html.erb"}
          )
        end
      end

      it "records a collection with no identifier without a template" do
        metrics = instrument("render_collection", identifier: nil, count: 0)

        assert_metric(
          metrics,
          name:       "rails.action_view.render.duration",
          dimensions: {"rails.action_view.render.kind" => "collection"}
        )
      end

      it "records a template outside the application by its full path" do
        metrics = instrument("render_partial", identifier: "/gems/engine/app/views/shared/_nav.html.erb")

        metric = assert_metric(metrics, name: "rails.action_view.render.duration")

        assert_equal "/gems/engine/app/views/shared/_nav.html.erb", metric.dimensions["rails.action_view.template"]
      end

      it "records the renders of a request, though they are logged at :debug" do
        metrics = semantic_logger_metrics { get article_url(:new) }

        assert_metric(
          metrics,
          name:       "rails.action_view.render.duration",
          dimensions: {"rails.action_view.render.kind" => "template",
                       "rails.action_view.template"    => "articles/new.html.erb"}
        )
      end
    end
  end
end
