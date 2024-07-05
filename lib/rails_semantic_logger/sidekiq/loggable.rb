module RailsSemanticLogger
  module Sidekiq
    module Loggable
      def included(base)
        super
        base.include(SemanticLogger::Loggable)
      end
    end
  end
end
