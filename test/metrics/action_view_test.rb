require_relative "../test_helper"

module Metrics
  class ActionViewTest < ActionDispatch::IntegrationTest
    describe RailsSemanticLogger::Metrics::ActionView do
      it "records through the logger of Action View, whose name is the meter" do
        assert_equal "ActionView::Base", RailsSemanticLogger::Metrics::ActionView.logger.name
      end

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

      it "records a gem's template by its path from its views" do
        metrics = instrument("render_partial",
                             identifier: "/home/deploy/gems/devise-4.9.4/app/views/devise/_links.html.erb")

        metric = assert_metric(metrics, name: "rails.action_view.render.duration")

        assert_equal "devise/_links.html.erb", metric.dimensions["rails.action_view.template"]
      end

      it "records no template outside any views directory" do
        metrics = instrument("render_template", identifier: "/tmp/inline.erb")

        metric = assert_metric(metrics, name: "rails.action_view.render.duration")

        refute metric.dimensions.key?("rails.action_view.template")
      end

      it "detaches only the listeners that log Rendering, when the log subscriber attaches" do
        name      = "render_template.action_view"
        delegates = -> { ActiveSupport::Notifications.notifier.all_listeners_for(name).map { |l| l.instance_variable_get(:@delegate) } }
        start     = RailsSemanticLogger::ActionView::LogSubscriber::Start

        assert_equal(1, delegates.call.count { |delegate| delegate.is_a?(start) })

        RailsSemanticLogger::ActionView::LogSubscriber.send(:detach_start_listeners, name)
        remaining = delegates.call

        assert_equal(0, remaining.count { |delegate| delegate.is_a?(start) })
        assert(remaining.any?(RailsSemanticLogger::Metrics::ActionView), "the metrics were detached too")
      ensure
        ActiveSupport::Notifications.subscribe(name, start.new) if delegates.call.none?(start)
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
