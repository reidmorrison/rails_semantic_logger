module ActiveSupport
  module TaggedLogging
    # Semantic Logger already does tagged logging
    def self.new(logger)
      logger
    end
  end
end
