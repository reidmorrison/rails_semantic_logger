ActionCable::Connection::TaggedLoggerProxy

module ActionCable
  module Connection
    class TaggedLoggerProxy
      # As of Rails 5 Beta 3
      def tag_logger(*tags, &block)
        logger.tagged(*tags, &block)
      end
    end
  end
end
