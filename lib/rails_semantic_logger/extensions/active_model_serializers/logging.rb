# Patch ActiveModelSerializers logger
require "active_model_serializers/logging"

module ActiveModelSerializers
  module Logging
    include SemanticLogger::Loggable

    private

    def tag_logger(*tags, &block)
      logger.tagged(*tags, &block)
    end
  end

  class SerializableResource
    include SemanticLogger::Loggable
  end
end
