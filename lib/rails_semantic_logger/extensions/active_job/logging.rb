# Patch ActiveJob logger
require "active_job/logging"

module ActiveJob
  module Logging
    include SemanticLogger::Loggable

    private

    undef_method :tag_logger
    def tag_logger(*tags, &block)
      logger.tagged(*tags, &block)
    end
  end
end
