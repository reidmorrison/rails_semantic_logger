module RailsSemanticLogger
  module DelayedJob
    class Plugin < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.before(:execute) do |job, &block|
          ::SemanticLogger.reopen
        end
      end
    end
  end
end
