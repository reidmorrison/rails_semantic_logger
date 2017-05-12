Rails::Rack::Logger

# Replace rack started message with a semantic equivalent
module Rails
  module Rack
    class Logger
      @logger = SemanticLogger['Rack']

      def self.logger
        @logger
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

      # Leave out any named tags with a nil value
      def compute_named_tags(request) # :doc:
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

    end
  end
end

