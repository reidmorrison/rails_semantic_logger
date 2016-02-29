ActionCable::Connection::TaggedLoggerProxy

module ActionCable
  module Connection
    class TaggedLoggerProxy
      # As of Rails 5 Beta 3
      def tag_logger(*tags, &block)
        logger.tagged(*tags, &block)
      end

      # Rails 5 Beta 1,2. TODO: Remove once Rails 5 is GA
      def tag(logger, &block)
        current_tags = tags - logger.tags
        logger.tagged(*current_tags, &block)
      end
    end
  end
end
