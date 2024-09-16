module RailsSemanticLogger
  module Rackup
    module Server
      def daemonize_app
        super
        SemanticLogger.reopen
      end
    end
  end
end

Rackup::Server.prepend(RailsSemanticLogger::Rackup::Server)
