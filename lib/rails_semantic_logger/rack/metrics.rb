require "action_dispatch/http/request"
require "rack/body_proxy"

module RailsSemanticLogger
  module Rack
    # Rack middleware that records `http.server.request.duration`, OpenTelemetry's stable metric for
    # the duration of an HTTP server request, in seconds, with its attributes as dimensions.
    #
    # It times the whole request as the server sees it: from when the request reaches it until the
    # response body is closed, so that streamed bodies are included. The engine places it just
    # before ActionDispatch::ShowExceptions, so it sees the status of the error pages that
    # ShowExceptions renders, and the exception class of any exception that escapes it.
    #
    # Knows: OpenTelemetry's attribute rules for HTTP server requests.
    # Asks:  RailsSemanticLogger::Metrics.logger to record the metric.
    class Metrics
      NAME = "http.server.request.duration".freeze

      # The methods that OpenTelemetry knows. Any other is recorded as "_OTHER", so that a client
      # cannot grow the number of series by inventing methods.
      KNOWN_METHODS = Set.new(%w[CONNECT DELETE GET HEAD OPTIONS PATCH POST PUT QUERY TRACE]).freeze

      # Rails adds this optional format segment to every route, which OpenTelemetry's action_pack
      # instrumentation leaves out of http.route too.
      FORMAT_SEGMENT = "(.:format)".freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        start                 = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        status, headers, body = @app.call(env)
        body                  = ::Rack::BodyProxy.new(body) { record(env, start, status, nil) }
        [status, headers, body]
      rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then raised again
        record(env, start, nil, e)
        raise
      end

      private

      def record(env, start, status, exception)
        duration_ms = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000
        RailsSemanticLogger::Metrics.logger.time(NAME, duration:   duration_ms,
                                                       dimensions: dimensions(env, status, exception))
      end

      def dimensions(env, status, exception)
        request    = ActionDispatch::Request.new(env)
        # The method as the client sent it: Request#request_method raises for a method Rails does not know.
        method     = env["REQUEST_METHOD"]
        dimensions = {
          "http.request.method" => KNOWN_METHODS.include?(method) ? method : "_OTHER",
          "url.scheme"          => request.scheme
        }
        route = route(request)
        dimensions["http.route"]                = route if route
        dimensions["http.response.status_code"] = status.to_i if status
        error_type                              = error_type(status, exception)
        dimensions["error.type"]                = error_type if error_type
        dimensions
      end

      # The route template that matched, such as "/articles/:id", with the application's root. Nil when
      # no route matched: OpenTelemetry forbids substituting the path.
      def route(request)
        pattern = request.route_uri_pattern
        return unless pattern

        "#{request.script_name}#{pattern.delete_suffix(FORMAT_SEGMENT)}"
      end

      # The exception class when one escaped, the status code for a server error, and none otherwise:
      # OpenTelemetry does not count a 4xx as an error of the server.
      def error_type(status, exception)
        return exception.class.name if exception

        status.to_s if status.to_i >= 500
      end
    end
  end
end
