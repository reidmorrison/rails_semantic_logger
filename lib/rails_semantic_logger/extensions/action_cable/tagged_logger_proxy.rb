require "action_cable/connection/tagged_logger_proxy"

module ActionCable
  module Connection
    class TaggedLoggerProxy
      def tag(logger, &)
        current_tags = tags - (logger.respond_to?(:tags) ? Array(logger.tags) : [])
        logger.tagged(*current_tags, &)
      end
    end
  end
end
