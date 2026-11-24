module RailsSemanticLogger
  module Metrics
    # Records the metrics of Action Controller. No OpenTelemetry convention covers them (the request
    # itself is http.server.request.duration, see RailsSemanticLogger::Rack::Metrics), so they are
    # named under `rails.action_controller`.
    class ActionController < Subscriber
      # How long the controller took to process the action, without the middleware.
      def process_action(event)
        payload    = event.payload
        dimensions = {"code.function.name" => "#{payload[:controller]}##{payload[:action]}"}
        status     = status(payload)
        dimensions["http.response.status_code"] = status if status
        dimensions["error.type"]                = payload[:exception].first if payload[:exception]
        time("rails.action_controller.process_action.duration", event, dimensions)
      end

      def halted_callback(event)
        increment("rails.action_controller.halted_callbacks",
                  "rails.action_controller.filter" => filter(event.payload[:filter]))
      end

      # Rails 8.1+.
      def rescue_from_callback(event)
        increment("rails.action_controller.rescued_exceptions", "error.type" => event.payload[:exception].class.name)
      end

      def redirect_to(event)
        payload    = event.payload
        dimensions = {}
        dimensions["http.response.status_code"] = payload[:status] if payload[:status]
        function = function(payload[:request])
        dimensions["code.function.name"] = function if function
        increment("rails.action_controller.redirects", dimensions)
      end

      # Rails 8.1+, with action_on_open_redirect = :notify.
      def open_redirect(_event)
        increment("rails.action_controller.unsafe_redirects", "rails.action_controller.redirect.kind" => "open")
      end

      # Rails 8.1+, with action_on_path_relative_redirect = :notify.
      def unsafe_redirect(_event)
        increment("rails.action_controller.unsafe_redirects",
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
        increment("rails.action_controller.csrf_events", "rails.action_controller.csrf.reason" => reason)
      end

      # The status of the response, or the status Rails renders for the exception that the action raised.
      def status(payload)
        return payload[:status] if payload[:status]
        return unless payload[:exception]

        ::ActionDispatch::ExceptionWrapper.status_code_for_exception(payload[:exception].first)
      end

      # A callback named by a method keeps its name; any other, such as a block, is named by its class,
      # so that the number of series stays bounded.
      def filter(filter)
        filter.is_a?(Symbol) || filter.is_a?(String) ? filter.to_s : filter.class.name
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
