# Patch ActiveJob logger
require "active_job/logging"

module ActiveJob
  module Logging
    include SemanticLogger::Loggable

    private

    undef_method :tag_logger
    def tag_logger(*tags, &block)
      if logger.respond_to?(:tagged)
        logger.tagged(*tags, &block)
      else
        yield
      end
    end
  end
end
