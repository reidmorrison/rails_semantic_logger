Rails::Rack::Logger

# Drop rack Started message to debug level message
module Rails
  module Rack
    class Logger
      def self.logger
        @logger
      end

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
        self.class.logger
      end

      @logger = SemanticLogger['Rack']
      @logger.extend(LogInfoAsDebug)
    end
  end
end
