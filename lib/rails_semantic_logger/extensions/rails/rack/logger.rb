Rails::Rack::Logger

# Replace rack started message with a semantic equivalent
module Rails
  module Rack
    class Logger
      @@logger = SemanticLogger['Rack']

      def self.logger
        @@logger
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

    end
  end
end

