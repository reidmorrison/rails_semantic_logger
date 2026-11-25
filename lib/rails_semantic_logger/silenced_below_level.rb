module RailsSemanticLogger
  # Lets Active Support leave a log subscriber out of an event that it would not log, as Rails' own
  # log subscribers are left out below the level they declare with `subscribe_log_level`.
  #
  # ActiveSupport::Notifications asks each subscriber `silenced?` each time an event starts, and
  # builds no event, nor times it, once every listener of the event is silenced. A subscriber that
  # never answers true keeps every event that it subscribes to instrumented, whatever is logged.
  #
  # Knows: when a log subscriber logs nothing for an event.
  # Asks:  the subscriber for the highest level at which it can log the event (#log_level_of), and
  #        for its logger.
  #
  # An event is silenced only when its handler would log nothing at all: the subscriber gives the
  # highest level that the handler can log it at, such as :error for a job that may fail, never the
  # level of its usual entry. An event that it gives no level for is never silenced.
  module SilencedBelowLevel
    def silenced?(name)
      level = log_level_of(name)
      return false unless level

      logger.nil? || !logger.public_send(:"#{level}?")
    end
  end
end
