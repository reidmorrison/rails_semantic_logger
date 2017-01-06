Rails::Rack::Logger

# Replace rack started message with a semantic equivalent
module Rails
  module Rack
    class Logger
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

    end
  end
end

