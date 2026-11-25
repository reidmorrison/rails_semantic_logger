require "action_dispatch/http/request"
require "rack/body_proxy"

module RailsSemanticLogger
  module Rack
    # Rack middleware that records `http.server.request.duration`, OpenTelemetry's stable metric for
    # the duration of an HTTP server request, in seconds, with its attributes as dimensions.
    #
    # It times the whole request as the server sees it: from when the request reaches it until the
    # response body is closed, so that streamed bodies are included. The engine places it first in
    # the middleware stack, so it sees every request, the status of the error pages that
    # ActionDispatch::ShowExceptions renders, and the class of any exception that escapes. A
    # hijacked connection, such as a WebSocket, is not an HTTP response, so it is not recorded.
    #
    # Knows: OpenTelemetry's attribute rules for HTTP server requests.
    # Asks:  the Rack logger to record the metric.
    class Metrics
      NAME = "http.server.request.duration".freeze

      # The methods that OpenTelemetry knows. Any other is recorded as "_OTHER", so that a client
      # cannot grow the number of series by inventing methods.
      KNOWN_METHODS = Set.new(%w[CONNECT DELETE GET HEAD OPTIONS PATCH POST PUT QUERY TRACE]).freeze

      # Rails adds this optional format segment to every route, which OpenTelemetry's action_pack
      # instrumentation leaves out of http.route too.
      FORMAT_SEGMENT = "(.:format)".freeze

      def initialize(app)
        @app    = app
        @mounts = Concurrent::Map.new
        # The logger of Rack, whose requests it measures: the name of the logger that records a metric
        # is its meter.
        @logger = SemanticLogger[::Rack]
      end

      def call(env)
        start                 = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        arrival               = Arrival.new(env, @mounts)
        status, headers, body = @app.call(env)
        # A hijacked connection, such as a WebSocket, has no HTTP response to time.
        return [status, headers, body] if status.to_i < 100

        route = !cascaded?(headers)
        body  = ::Rack::BodyProxy.new(body) { record(env, start, status, nil, arrival: arrival, route: route) }
        [status, headers, body]
      rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then raised again
        record(env, start, nil, e, arrival: arrival)
        raise
      end

      private

      # Records the request. Never raises, so that a metric cannot fail the request, nor hide the
      # exception that it raised.
      def record(env, start, status, exception, arrival:, route: true)
        duration_ms = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000
        @logger.time(NAME, duration: duration_ms, dimensions: dimensions(env, status, exception, arrival, route))
      rescue StandardError
        nil
      end

      def dimensions(env, status, exception, arrival, route)
        request    = ActionDispatch::Request.new(env)
        # The method as the client sent it, before Rack::MethodOverride: Request#request_method raises
        # for a method that Rails does not know.
        method     = env["rack.methodoverride.original_method"] || env["REQUEST_METHOD"]
        dimensions = {
          "http.request.method" => KNOWN_METHODS.include?(method) ? method : "_OTHER",
          "url.scheme"          => request.scheme
        }
        template = arrival&.route(request) if route && !unrouted?(env, exception)
        dimensions["http.route"]                = template if template
        dimensions["http.response.status_code"] = status.to_i if status
        error_type                              = error_type(status, exception)
        dimensions["error.type"]                = error_type if error_type
        dimensions
      end

      # Whether no route served the request, though the router left on it a route that it tried: Rails
      # turns a route that passed the request on into a routing error, which escapes, or which
      # ActionDispatch::ShowExceptions keeps on the request as it renders the 404. A routing error that a
      # controller raised, as a way to answer 404, was routed. (ActionDispatch::DebugExceptions, which
      # renders the error itself when detailed exceptions are shown, as in development, leaves no trace
      # of it, so there the route that passed the request on is recorded.)
      def unrouted?(env, exception)
        return false if env["action_controller.instance"]

        routing_error?(exception) || routing_error?(env["action_dispatch.exception"])
      end

      def routing_error?(exception)
        defined?(::ActionController::RoutingError) && exception.is_a?(::ActionController::RoutingError)
      end

      # Whether the route that matched passed the request on (X-Cascade: pass), so that no route served
      # it, in a Rack application where no Rails middleware turns that into a routing error.
      def cascaded?(headers)
        (headers["x-cascade"] || headers["X-Cascade"]) == "pass"
      end

      # The exception class when one escaped, the status code for a server error, and none otherwise:
      # OpenTelemetry does not count a 4xx as an error of the server.
      def error_type(status, exception)
        # An anonymous exception class has no name: OpenTelemetry's fallback for an unknown error.
        return exception.class.name || "_OTHER" if exception

        status.to_s if status.to_i >= 500
      end

      # The request as it reached the middleware: the application's root (SCRIPT_NAME) and routes, so
      # that the route recorded is built only from route templates, never from the path that a mount
      # matched, which can hold values, such as a locale.
      class Arrival
        # mounts: kept by the middleware, so that each is searched for once: the application's routes
        # that mount each engine, by the engine's routes, and the engine's route of each template, by the
        # engine's routes and the template.
        def initialize(env, mounts)
          @root   = env["SCRIPT_NAME"].to_s
          @routes = env["action_dispatch.routes"]
          @mounts = mounts
        end

        # The route template that served the request, such as "/articles/:id", from the application's
        # root. Nil when no route matched: OpenTelemetry forbids substituting the path.
        #
        # The innermost router that matched leaves its template on the request. That is the
        # application's own router for its routes and for a mounted Rack application, whose template is
        # the mount. A mounted engine's router replaces it with its own template, below the mount, and
        # its routes with its own, so the template of the application's mount of that engine goes before
        # it. An engine that passes the request on leaves its routes on the request, but not its mount:
        # the router restores SCRIPT_NAME, so a request whose SCRIPT_NAME is the application's root was
        # served by the application's own routes.
        def route(request)
          pattern = request.route_uri_pattern
          return unless pattern

          inner   = request.routes
          mounted = request.script_name.to_s.delete_prefix(@root)
          mount   = inner.equal?(@routes) || inner.nil? || mounted.empty? ? "" : mount_template(inner, mounted, pattern)
          return unless mount

          template = strip(pattern)
          # The engine's root, its own root route or a Rack application that it mounts at its root, is
          # recorded as the engine's mount, as its URL is.
          template = "" if template == "/" && !mount.empty?
          "#{@root}#{mount}#{template}"
        end

        private

        # The template of the application's route that mounts the engine whose routes these are, or nil
        # when none does, such as an engine that another engine mounts, which is then recorded without a
        # route.
        #
        # The mount must account for the path that the mounts matched, through the engine's route that
        # served the request, whose template is on the request: all of it when that is a route of the
        # engine's own, or all but the rest, which that route matches, when it is a Rack application
        # that the engine mounts. Otherwise the engine passed the request on and another mount served
        # it, whose template is not known: no route is recorded.
        def mount_template(inner, mounted, pattern)
          served = served_by(inner, pattern)
          mounts = @mounts.compute_if_absent(inner) { mounts_of(inner) }
          mount  = mounts.find do |route|
            match = route.path.match(mounted)
            match && served.any? { |candidate| below?(candidate, match.post_match) }
          end
          # The template below it starts with "/", so that of a mount at the root ends without one.
          strip(mount.path.spec.to_s).delete_suffix("/") if mount
        end

        # The engine's routes with the template `pattern`: several when they differ only in their
        # constraints.
        def served_by(inner, pattern)
          @mounts.compute_if_absent([inner, pattern]) do
            inner.routes.select { |route| route.path.spec.to_s == pattern }
          end
        end

        # Whether the engine's `route` matches `rest`, the path below the engine's mount: none for a
        # route of the engine's own, and all of it for a Rack application that the engine mounts. The
        # engine's mount at the root leaves no "/" before the rest, and a mount at the engine's root
        # leaves no rest.
        def below?(route, rest)
          return rest.empty? if route.path.anchored

          match = route.path.match(rest.start_with?("/") ? rest : "/#{rest}")
          match ? match.post_match.empty? : false
        end

        # The application's routes that mount the engine whose routes these are.
        def mounts_of(inner)
          (@routes&.routes || []).select do |route|
            app = route.app.respond_to?(:app) ? route.app.app : route.app
            app.respond_to?(:routes) && app.routes.equal?(inner)
          end
        end

        def strip(template)
          template.delete_suffix(FORMAT_SEGMENT)
        end
      end
    end
  end
end
