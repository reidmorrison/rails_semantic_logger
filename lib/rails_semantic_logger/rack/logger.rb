require "active_support/core_ext/time/conversions"
require "active_support/core_ext/object/blank"
require "active_support/log_subscriber"
require "action_dispatch/http/request"
require "rack/body_proxy"

module RailsSemanticLogger
  module Rack
    class Logger < ActiveSupport::LogSubscriber
      class << self
        attr_reader :logger
        attr_accessor :started_request_log_level
      end

      def initialize(app, taggers = nil)
        @app     = app
        @taggers = taggers || []
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        # Check for named tags (Hash)
        if @taggers && !@taggers.empty?
          tags = @taggers.is_a?(Hash) ? compute_named_tags(request) : compute_tags(request)
          logger.tagged(tags) { call_app(request, env) }
        else
          call_app(request, env)
        end
      end

      private

      @logger                    = SemanticLogger["Rack"]
      @started_request_log_level = :debug

      def call_app(request, env)
        instrumenter        = ActiveSupport::Notifications.instrumenter
        handle              = instrumenter.build_handle "request.action_dispatch", request: request
        instrumenter_finish = lambda {
          handle.finish
        }
        handle.start

        logger.send(self.class.started_request_log_level) { started_request_message(request) }
        status, headers, body = @app.call(env)
        body                  = ::Rack::BodyProxy.new(body, &instrumenter_finish)
        [status, headers, body]
      rescue Exception
        instrumenter_finish.call
        raise
      end

      def started_request_message(request)
        {
          message: "Started",
          payload: {
            method: request.request_method,
            path:   request.filtered_path,
            ip:     request.remote_ip
          }
        }
      end

      def compute_tags(request)
        @taggers.collect do |tag|
          case tag
          when Proc
            tag.call(request)
          when Symbol
            request.send(tag)
          else
            tag
          end
        end
      end

      # Leave out any named tags with a nil value
      def compute_named_tags(request)
        tagged = {}
        @taggers.each_pair do |tag, value|
          resolved    =
            case value
            when Proc
              value.call(request)
            when Symbol
              request.send(value)
            else
              value
            end
          tagged[tag] = resolved unless resolved.nil?
        end
        tagged
      end

      def logger
        self.class.logger
      end
    end
  end
end
