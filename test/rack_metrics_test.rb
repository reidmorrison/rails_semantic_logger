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

  class RequestTest < ActionDispatch::IntegrationTest
    describe "the application's middleware" do
      it "places the request metrics just before ShowExceptions" do
        middleware = Rails.application.middleware.map(&:klass)

        assert_equal ::ActionDispatch::ShowExceptions,
                     middleware[middleware.index(RailsSemanticLogger::Rack::Metrics) + 1]
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
