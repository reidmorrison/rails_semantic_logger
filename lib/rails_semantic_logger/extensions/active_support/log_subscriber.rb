if ActiveSupport::VERSION::STRING == "7.1.1"
  require "active_support/log_subscriber"

  module ActiveSupport
    class LogSubscriber
      # @override Rails 7.1
      def silenced?(event)
        native_log_level = @event_levels.fetch(event, ::Logger::Severity::FATAL)
        logger.nil? || SemanticLogger::Levels.index(logger.level) > SemanticLogger::Levels.index(native_log_level)
      end
    end
  end
end
