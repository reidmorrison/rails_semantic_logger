module RailsSemanticLogger
  module Metrics
    # Records how long each operation on an ActiveSupport::Cache store takes, as
    # `rails.cache.operation.duration`, since no OpenTelemetry convention covers caches yet.
    class Cache < Subscriber
      # The logger of Active Support's cache, whose name is the meter of its metrics.
      def self.logger
        ::ActiveSupport::Cache::Store.logger
      end

      # The dimensions it records, which no sensitive key redacts (see Metrics.declare_dimension_keys).
      DIMENSION_KEYS = %w[rails.cache.operation.name rails.cache.store rails.cache.hit].freeze

      NAME = "rails.cache.operation.duration".freeze

      # The cache events that Active Support instruments, each "<event>.active_support".
      EVENTS = %w[
        cache_read cache_read_multi cache_generate cache_fetch_hit cache_write cache_write_multi
        cache_delete cache_delete_multi cache_delete_matched cache_exist? cache_increment
        cache_decrement cache_cleanup cache_prune
      ].freeze

      EVENTS.each do |event_name|
        operation = event_name.delete_prefix("cache_").delete_suffix("?")
        define_method(event_name) { |event| record(operation, event) }
      end

      private

      # By operation and store, and for a read, whether it was a hit.
      def record(operation, event)
        payload    = event.payload
        dimensions = {"rails.cache.operation.name" => operation}
        dimensions["rails.cache.store"] = payload[:store].to_s if payload[:store]
        dimensions["rails.cache.hit"]   = payload[:hit] if operation == "read" && payload.key?(:hit)
        time(NAME, event, dimensions)
      end
    end
  end
end
