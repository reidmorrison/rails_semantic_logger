require_relative "test_helper"

# Verifies RailsSemanticLogger::ActionView::LogSubscriber emits structured payloads for
# template, partial, collection, and layout rendering. The upstream ActionView log subscriber
# is identical across Rails 7.2 / 8.0 / 8.1, so no version-specific behavior is expected here.
class ActionViewTest < ActionDispatch::IntegrationTest
  describe RailsSemanticLogger::ActionView::LogSubscriber do
    # Drives the real subscriber by emitting the ActiveSupport notification it listens to, then
    # returns the captured ActionView log events. Identifiers are rooted under Rails.root so the
    # subscriber's from_rails_root stripping is exercised too.
    def instrument(name, payload)
      events = semantic_logger_events do
        # The block stands in for the actual view render the notification wraps.
        ActiveSupport::Notifications.instrument("#{name}.action_view", payload) { :rendered }
      end
      events.select { |m| m.name == "ActionView" }
    end

    def view_path(relative)
      "#{Rails.root}/app/views/#{relative}"
    end

    describe "#render_partial" do
      it "strips the identifier and records allocations and gc_time" do
        events = instrument("render_partial", identifier: view_path("articles/_form.html.erb"))
        assert_equal 1, events.count, events

        rendered = events.first
        assert_equal "Rendered", rendered.message
        assert_equal :debug, rendered.level
        assert_equal "articles/_form.html.erb", rendered.payload[:partial]
        assert_kind_of Integer, rendered.payload[:allocations]
        assert_kind_of Float, rendered.payload[:gc_time]
      end

      it "records a cache hit" do
        events = instrument("render_partial",
                            identifier: view_path("articles/_form.html.erb"),
                            cache_hit:  :hit)
        assert_equal :hit, events.first.payload[:cache]
      end

      it "records a cache miss" do
        events = instrument("render_partial",
                            identifier: view_path("articles/_form.html.erb"),
                            cache_hit:  :miss)
        assert_equal :miss, events.first.payload[:cache]
      end

      it "omits cache when there is no cache_hit" do
        events = instrument("render_partial", identifier: view_path("articles/_form.html.erb"))
        refute events.first.payload.key?(:cache), events.first.payload
      end

      it "includes the layout it renders within" do
        events = instrument("render_partial",
                            identifier: view_path("articles/_form.html.erb"),
                            layout:     view_path("layouts/application.html.erb"))
        assert_equal "layouts/application.html.erb", events.first.payload[:within]
      end

      it "omits within when there is no layout" do
        events = instrument("render_partial", identifier: view_path("articles/_form.html.erb"))
        refute events.first.payload.key?(:within), events.first.payload
      end
    end

    describe "#render_collection" do
      it "records the count and cache hits" do
        events = instrument("render_collection",
                            identifier: view_path("articles/_article.html.erb"),
                            count:      3,
                            cache_hits: 2)
        assert_equal 1, events.count, events

        rendered = events.first
        assert_equal "Rendered", rendered.message
        assert_equal :debug, rendered.level
        assert_equal "articles/_article.html.erb", rendered.payload[:template]
        assert_equal 3, rendered.payload[:count]
        assert_equal 2, rendered.payload[:cache_hits]
        assert_kind_of Integer, rendered.payload[:allocations]
        assert_kind_of Float, rendered.payload[:gc_time]
      end

      it "omits cache_hits when caching is not in play" do
        events = instrument("render_collection",
                            identifier: view_path("articles/_article.html.erb"),
                            count:      3)
        refute events.first.payload.key?(:cache_hits), events.first.payload
      end

      it "falls back to 'templates' when the identifier is nil" do
        events = instrument("render_collection", identifier: nil, count: 0)
        assert_equal "templates", events.first.payload[:template]
      end
    end

    describe "#render_template" do
      it "records the template, layout, allocations, and gc_time" do
        # render_template.action_view also drives the Start subscriber, which emits a "Rendering"
        # event before the "Rendered" completion handled here.
        events = instrument("render_template",
                            identifier: view_path("welcome/index.html.erb"),
                            layout:     view_path("layouts/application.html.erb"))

        rendered = events.find { |m| m.message == "Rendered" }
        assert rendered, events
        assert_equal "welcome/index.html.erb", rendered.payload[:template]
        assert_equal "layouts/application.html.erb", rendered.payload[:within]
        assert_kind_of Integer, rendered.payload[:allocations]
        assert_kind_of Float, rendered.payload[:gc_time]
      end
    end

    describe "rendering a template within a layout (integration)" do
      def action_view_events(messages)
        messages.select { |m| m.name == "ActionView" }
      end

      it "logs the layout and template render" do
        messages = semantic_logger_events do
          get "/welcome/index"
        end

        av = action_view_events(messages)

        rendering_layout = av.find { |m| m.message == "Rendering layout" }
        assert rendering_layout, av
        assert_equal "layouts/application.html.erb", rendering_layout.payload[:template]

        rendering = av.find { |m| m.message == "Rendering" }
        assert rendering, av
        assert_equal "welcome/index.html.erb", rendering.payload[:template]

        rendered = av.find { |m| m.message == "Rendered" }
        assert rendered, av
        assert_equal "welcome/index.html.erb", rendered.payload[:template]
        assert_equal "layouts/application", rendered.payload[:within]

        rendered_layout = av.find { |m| m.message == "Rendered layout" }
        assert rendered_layout, av
        assert_equal "layouts/application.html.erb", rendered_layout.payload[:template]
      end

      it "includes allocations and gc_time on completed renders" do
        messages = semantic_logger_events do
          get "/welcome/index"
        end

        %w[Rendered].each do |message|
          event = action_view_events(messages).find { |m| m.message == message }
          assert event, messages
          assert event.payload.key?(:allocations), event.payload
          assert event.payload.key?(:gc_time), event.payload
        end

        rendered_layout = action_view_events(messages).find { |m| m.message == "Rendered layout" }
        assert rendered_layout, messages
        assert rendered_layout.payload.key?(:allocations), rendered_layout.payload
        assert rendered_layout.payload.key?(:gc_time), rendered_layout.payload
      end
    end
  end
end
