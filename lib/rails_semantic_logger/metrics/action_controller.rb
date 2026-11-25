module RailsSemanticLogger
  module Metrics
    # Records the metrics of Action Controller, from the events that Rails instruments for its own log
    # subscriber: when Rails adds or changes one, follow it here too. See the upstream source links at
    # the top of lib/rails_semantic_logger/action_controller/log_subscriber.rb.
    #
    # No OpenTelemetry convention covers them (the request
    # itself is http.server.request.duration, see RailsSemanticLogger::Rack::Metrics), so they are
    # named under `rails.action_controller`.
    class ActionController < Subscriber
      # The logger of Action Controller, whose name is the meter of its metrics.
      LOGGER_NAME = "ActionController::Base".freeze

      # The dimensions it records, which no sensitive key redacts (see Metrics.declare_dimension_keys).
      DIMENSION_KEYS = %w[
        code.function.name http.response.status_code error.type rails.action_controller.filter
        rails.action_controller.redirect.kind rails.action_controller.csrf.reason rails.cache.operation.name
      ].freeze

      # How long the controller took to process the action, without the middleware.
      def process_action(event)
        payload    = event.payload
        dimensions = {"code.function.name" => "#{payload[:controller]}##{payload[:action]}"}
        dimensions["http.response.status_code"] = payload[:status] if payload[:status]
        dimensions["error.type"]                = payload[:exception].first if payload[:exception]
        time("rails.action_controller.process_action.duration", event, dimensions)
      end

      def halted_callback(event)
        increment("rails.action_controller.halted_callbacks", "{callback}",
                  "rails.action_controller.filter" => filter(event.payload[:filter]))
      end

      # Rails 8.1+.
      def rescue_from_callback(event)
        increment("rails.action_controller.rescued_exceptions", "{exception}",
                  "error.type" => error_type(event.payload[:exception]))
      end

      def redirect_to(event)
        payload    = event.payload
        dimensions = {}
        dimensions["http.response.status_code"] = payload[:status] if payload[:status]
        function = function(payload[:request])
        dimensions["code.function.name"] = function if function
        increment("rails.action_controller.redirects", "{redirect}", dimensions)
      end

      # Rails 8.1+, with action_on_open_redirect = :notify.
      def open_redirect(_event)
        increment("rails.action_controller.unsafe_redirects", "{redirect}",
                  "rails.action_controller.redirect.kind" => "open")
      end

      # Rails 8.1+, with action_on_path_relative_redirect = :notify.
      def unsafe_redirect(_event)
        increment("rails.action_controller.unsafe_redirects", "{redirect}",
                  "rails.action_controller.redirect.kind" => "path_relative")
      end

      def send_file(event)
        time("rails.action_controller.send_file.duration", event)
      end

      def send_data(event)
        time("rails.action_controller.send_data.duration", event)
      end

      # Rails 8.2+, which reports these through events instead of logging them.
      def csrf_token_fallback(_event)
        csrf("token_fallback")
      end

      def csrf_request_blocked(_event)
        csrf("request_blocked")
      end

      def csrf_javascript_blocked(_event)
        csrf("javascript_blocked")
      end

      # Rails instruments the fragment cache only while enable_fragment_cache_logging is on.
      %w[write_fragment read_fragment exist_fragment? expire_fragment expire_page write_page].each do |operation|
        define_method(operation) do |event|
          time(
            "rails.action_controller.fragment_cache.duration",
            event,
            "rails.cache.operation.name" => operation.delete_suffix("?")
          )
        end
      end

      private

      def csrf(reason)
        increment("rails.action_controller.csrf_events", "{event}", "rails.action_controller.csrf.reason" => reason)
      end

      # A callback named by a method keeps its name; any other, such as a block, is named by its class,
      # so that the number of series stays bounded, or "_OTHER" for an anonymous class, which has no
      # name, as for an error.type.
      def filter(filter)
        filter.is_a?(Symbol) || filter.is_a?(String) ? filter.to_s : filter.class.name || "_OTHER"
      end

      # "ArticlesController#show": the controller and action handling the request, when known.
      def function(request)
        controller = request&.controller_instance
        return unless controller

        "#{controller.class.name}##{controller.action_name}"
      end
    end
  end
end
