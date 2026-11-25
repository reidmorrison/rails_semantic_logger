require_relative "test_helper"

class RackMetricsTest < Minitest::Test
  describe RailsSemanticLogger::Rack::Metrics do
    let(:status) { 200 }
    let(:route) { "/articles/:id(.:format)" }
    let(:app) do
      pattern  = route
      response = status
      lambda do |env|
        env["action_dispatch.route_uri_pattern"] = pattern if pattern
        [response, {}, ["body"]]
      end
    end
    let(:middleware) { RailsSemanticLogger::Rack::Metrics.new(app) }

    # Calls the middleware and closes the body, as a server does once it has sent the response.
    def request(env = ::Rack::MockRequest.env_for("http://example.com/articles/1"))
      semantic_logger_metrics do
        _status, _headers, body = middleware.call(env)
        body.close
      end
    end

    it "records the request duration in seconds once the body is closed" do
      env     = ::Rack::MockRequest.env_for("http://example.com/articles/1")
      metrics = semantic_logger_metrics { @body = middleware.call(env)[2] }

      assert_empty metrics, "recorded before the body was closed"

      metrics = semantic_logger_metrics { @body.close }

      assert_metric(
        metrics,
        name:       "http.server.request.duration",
        kind:       :histogram,
        unit:       "s",
        dimensions: {
          "http.request.method"       => "GET",
          "url.scheme"                => "http",
          "http.route"                => "/articles/:id",
          "http.response.status_code" => 200
        }
      )
    end

    it "prefixes the route with the application root" do
      env = ::Rack::MockRequest.env_for("https://example.com/blog/articles/1", "SCRIPT_NAME" => "/blog")

      metric = assert_metric(request(env), name: "http.server.request.duration")

      assert_equal "/blog/articles/:id", metric.dimensions["http.route"]
      assert_equal "https", metric.dimensions["url.scheme"]
    end

    it "records an unknown method as _OTHER" do
      env = ::Rack::MockRequest.env_for("http://example.com/articles/1", method: "PURGE")

      metric = assert_metric(request(env), name: "http.server.request.duration")

      assert_equal "_OTHER", metric.dimensions["http.request.method"]
    end

    describe "when the route that matched passed the request on" do
      let(:app) do
        lambda { |env|
          env["action_dispatch.route_uri_pattern"] = "/things/:id(.:format)"
          [404, {"x-cascade" => "pass"}, []]
        }
      end

      it "records no route" do
        metric = assert_metric(request, name: "http.server.request.duration")

        refute metric.dimensions.key?("http.route")
      end
    end

    describe "a routing error that a controller raised" do
      let(:app) do
        lambda do |env|
          env["action_dispatch.route_uri_pattern"] = "/articles/:id(.:format)"
          env["action_controller.instance"]        = Object.new
          raise ActionController::RoutingError, "Not Found"
        end
      end

      it "keeps the route that served the request" do
        metrics = semantic_logger_metrics do
          assert_raises(ActionController::RoutingError) { middleware.call(::Rack::MockRequest.env_for("http://example.com/articles/9")) }
        end

        assert_equal "/articles/:id",
                     assert_metric(metrics, name: "http.server.request.duration").dimensions["http.route"]
      end
    end

    describe "a hijacked connection" do
      let(:app) { ->(_env) { [-1, {}, []] } }

      it "records nothing" do
        metrics = semantic_logger_metrics { middleware.call(::Rack::MockRequest.env_for("http://example.com/cable")) }

        assert_empty metrics
      end
    end

    describe "when no route matched" do
      let(:route) { nil }
      let(:status) { 404 }

      it "records no route and no error.type for a 4xx" do
        metric = assert_metric(request, name: "http.server.request.duration")

        refute metric.dimensions.key?("http.route")
        refute metric.dimensions.key?("error.type")
        assert_equal 404, metric.dimensions["http.response.status_code"]
      end
    end

    describe "with a server error" do
      let(:status) { 503 }

      it "records the status code as the error.type" do
        metric = assert_metric(request, name: "http.server.request.duration")

        assert_equal "503", metric.dimensions["error.type"]
      end
    end

    describe "when an exception escapes" do
      let(:app) { ->(_env) { raise ArgumentError, "boom" } }

      it "records the exception class as the error.type, with no status code" do
        metrics = semantic_logger_metrics do
          assert_raises(ArgumentError) { middleware.call(::Rack::MockRequest.env_for("http://example.com/")) }
        end

        metric = assert_metric(metrics, name: "http.server.request.duration")

        assert_equal "ArgumentError", metric.dimensions["error.type"]
        refute metric.dimensions.key?("http.response.status_code")
      end
    end
  end

  describe "the route of a mounted engine" do
    let(:engine) do
      Class.new(::Rails::Engine) do
        def self.name = "RackMetricsTest::Engine"
      end
    end
    let(:routes) { ActionDispatch::Routing::RouteSet.new }
    let(:middleware) { RailsSemanticLogger::Rack::Metrics.new(routes) }

    before do
      engine.routes.draw do
        get "posts/:id", to: ->(_env) { [200, {}, ["post"]] }
        get "drafts/:id", to: ->(_env) { [404, {"x-cascade" => "pass"}, []] }
      end
    end

    def route_of(path)
      env    = ::Rack::MockRequest.env_for("http://example.com#{path}", "action_dispatch.routes" => routes)
      metric = assert_metric(
        semantic_logger_metrics do
          _status, _headers, body = middleware.call(env)
          body.close
        end,
        name: "http.server.request.duration"
      )
      metric.dimensions["http.route"]
    end

    it "records an engine mounted at the root by its own template" do
      mounted = engine
      routes.draw { mount mounted, at: "/" }

      assert_equal "/posts/:id", route_of("/posts/5")
    end

    it "records the application's route that served a request an engine passed on, without the engine's mount" do
      mounted = engine
      routes.draw do
        mount mounted, at: "/blog"
        get "blog/drafts/:id", to: ->(_env) { [200, {}, ["draft"]] }
      end

      assert_equal "/blog/drafts/:id", route_of("/blog/drafts/5")
    end

    it "records no route for a request that an engine passed on to another mount" do
      mounted = engine
      routes.draw do
        mount mounted, at: "/blog"
        mount ->(_env) { [200, {}, ["legacy"]] }, at: "/blog/drafts"
      end

      assert_nil route_of("/blog/drafts/5")
    end

    it "records the route of a Rack application that an engine mounts, below the engine's mount" do
      mounted = engine
      mounted.routes.draw { mount ->(_env) { [200, {}, ["admin"]] }, at: "/admin" }
      routes.draw do
        mount mounted, at: "/blog"
        mount mounted, at: "/journal", as: "journal"
      end

      assert_equal "/journal/admin", route_of("/journal/admin/users")
    end

    it "records the route of a Rack application that an engine mounted at the root mounts" do
      mounted = engine
      mounted.routes.draw { mount ->(_env) { [200, {}, ["admin"]] }, at: "/admin" }
      routes.draw { mount mounted, at: "/" }

      assert_equal "/admin", route_of("/admin/users")
    end

    it "records the route of a Rack application that an engine mounts at a dynamic path" do
      mounted = engine
      mounted.routes.draw { mount ->(_env) { [200, {}, ["admin"]] }, at: "/:tenant/admin" }
      routes.draw { mount mounted, at: "/blog" }

      assert_equal "/blog/:tenant/admin", route_of("/blog/acme/admin/users")
    end

    it "records the mount of the engine that mounts the Rack application, whatever the order of the mounts" do
      mounted = engine
      mounted.routes.draw { mount ->(_env) { [200, {}, ["admin"]] }, at: "/admin" }
      routes.draw do
        mount mounted, at: "/:locale"
        mount mounted, at: "/", as: "root_blog"
      end

      assert_equal "/admin", route_of("/admin/users")
    end

    it "records the route of the Rack application that served, of several that an engine mounts at one template" do
      mounted = engine
      mounted.routes.draw do
        mount ->(_env) { [200, {}, ["a"]] }, at: "/:id/admin", constraints: {id: /\d+/}
        mount ->(_env) { [200, {}, ["b"]] }, at: "/:id/admin", constraints: {id: /[a-z]+/}, as: "lettered"
      end
      routes.draw { mount mounted, at: "/blog" }

      assert_equal "/blog/:id/admin", route_of("/blog/acme/admin/x")
    end

    it "records the engine's own root route as the engine's mount" do
      mounted = engine
      mounted.routes.draw { root to: ->(_env) { [200, {}, ["home"]] } }
      routes.draw do
        mount mounted, at: "/blog"
        mount mounted, at: "/:locale", as: "localized"
      end

      assert_equal "/blog", route_of("/blog")
      assert_equal "/:locale", route_of("/en")
    end

    it "records a Rack application that an engine mounts at its root as the engine's mount" do
      mounted = engine
      mounted.routes.draw { mount ->(_env) { [200, {}, ["home"]] }, at: "/" }
      routes.draw { mount mounted, at: "/blog" }

      assert_equal "/blog", route_of("/blog/anything")
    end

    it "records no route for a request passed on to a mount whose template starts like the engine's path" do
      mounted = engine
      routes.draw do
        mount mounted, at: "/blog"
        mount ->(_env) { [200, {}, ["legacy"]] }, at: "/blog/blog"
      end

      assert_nil route_of("/blog/blog/drafts/5")
    end
  end

  class RequestTest < ActionDispatch::IntegrationTest
    describe "the application's middleware" do
      it "places the request metrics first, so that it sees every request" do
        assert_equal RailsSemanticLogger::Rack::Metrics, Rails.application.middleware.first.klass
      end

      it "records a mounted Rack application by its mount path" do
        metrics = semantic_logger_metrics { get "/mounted/anything" }

        metric = assert_metric(metrics, name: "http.server.request.duration")

        assert_equal "/mounted", metric.dimensions["http.route"]
      end

      it "records a mounted engine's route below its mount path" do
        metric = assert_metric(semantic_logger_metrics { get "/blog/posts/5" }, name: "http.server.request.duration")

        assert_equal "/blog/posts/:id", metric.dimensions["http.route"]
      end

      it "records routes under a dynamic segment by their templates, never by the path" do
        rack_app = assert_metric(semantic_logger_metrics do
          get "/en/localized/x"
        end, name: "http.server.request.duration")
        engine = assert_metric(semantic_logger_metrics do
          get "/fr/news/posts/5"
        end, name: "http.server.request.duration")

        assert_equal "/:locale/localized", rack_app.dimensions["http.route"]
        assert_equal "/:locale/news/posts/:id", engine.dimensions["http.route"]
      end

      it "records no route for a request that a route passed on" do
        metrics = semantic_logger_metrics do
          get "/cascading/5"
        rescue ActionController::RoutingError
          nil
        end

        metric = assert_metric(metrics, name: "http.server.request.duration")

        refute metric.dimensions.key?("http.route"), metric.dimensions
      end

      it "records the method that the client sent, before a method override" do
        metrics = semantic_logger_metrics do
          post article_url(1), params: {_method: "delete"}
        rescue AbstractController::ActionNotFound
          nil
        end

        metric = assert_metric(metrics, name: "http.server.request.duration")

        assert_equal "POST", metric.dimensions["http.request.method"]
      end

      it "records each request" do
        metrics = semantic_logger_metrics { get article_url(:new) }

        assert_metric(
          metrics,
          name:       "http.server.request.duration",
          dimensions: {
            "http.request.method"       => "GET",
            "url.scheme"                => "http",
            "http.route"                => "/articles/new",
            "http.response.status_code" => 200
          }
        )
      end
    end
  end
end
