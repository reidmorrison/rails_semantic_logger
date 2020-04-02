# Patch ActiveJob logger
require 'active_job/logging'

module ActiveJob
  module Logging
    include SemanticLogger::Loggable

    private

    def tag_logger(*tags, &block)
      logger.tagged(*tags, &block)
    end
  end
end

