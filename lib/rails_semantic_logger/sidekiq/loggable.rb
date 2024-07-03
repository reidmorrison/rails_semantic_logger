module RailsSemanticLogger
  module Sidekiq
    module Loggable
      def included(base)
        base.include(SemanticLogger::Loggable)
        super
      end
    end
  end
end
