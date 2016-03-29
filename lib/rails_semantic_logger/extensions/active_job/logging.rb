# Patch ActiveJob logger
require 'active_job/logging'

module ActiveJob::Logging
  private
  def tag_logger(*tags, &block)
    logger.tagged(*tags, &block)
  end
end
