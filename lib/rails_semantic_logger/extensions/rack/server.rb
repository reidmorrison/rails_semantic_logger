module RailsSemanticLogger
  module Rack
    module Server
      def daemonize_app
        super
        SemanticLogger.reopen
      end
    end
  end
end

Rack::Server.prepend(RailsSemanticLogger::Rack::Server)
