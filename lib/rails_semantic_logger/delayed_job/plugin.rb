module RailsSemanticLogger
  module DelayedJob
    class Plugin < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.before(:execute) do |_job|
          ::SemanticLogger.reopen
        end
      end
    end
  end
end
