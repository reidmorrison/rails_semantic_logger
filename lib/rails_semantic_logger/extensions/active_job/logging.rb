# Patch ActiveJob logger
ActiveJob::Logging

module ActiveJob::Logging
  private
  def tag_logger(*tags, &block)
    logger.tagged(*tags, &block)
  end
end
