Rails::Rack::Logger

# Drop rack Started message to debug level message
module Rails
  module Rack
    class Logger
      private

      module LogInfoAsDebug
        def info(*args, &block)
          debug(*args, &block)
        end
        def info?
          debug?
        end
      end

      def logger
        @logger ||= begin
          logger = SemanticLogger['Rack']
          logger.extend(LogInfoAsDebug)
          logger
        end
      end

    end
  end
end
