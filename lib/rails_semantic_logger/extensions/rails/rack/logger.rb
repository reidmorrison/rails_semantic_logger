Rails::Rack::Logger

# Replace rack started message with a semantic equivalent
module Rails
  module Rack
    class Logger
      mattr_accessor :named_tags

      @logger = SemanticLogger['Rack']

      def self.logger
        @logger
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        proc = -> { call_app(request, env) }
        proc = -> { logger.tagged(compute_tags(request), &proc) } if @taggers && !@taggers.empty?
        named_tags ? SemanticLogger.named_tagged(compute_named_tags(request), &proc) : proc.call
      end

      def started_request_message(request)
        {
          message: 'Started',
          payload: {
            method: request.request_method,
            path:   request.filtered_path,
            ip:     request.ip
          }
        }
      end

      private

      def logger
        self.class.logger
      end

      def compute_named_tags(request) # :doc:
        tagged = {}
        named_tags.each_pair do |tag, value|
          resolved =
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

    end
  end
end

