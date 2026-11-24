require_relative "../test_helper"

module Metrics
  class CacheTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::Cache do
      let(:store) { ActiveSupport::Cache::MemoryStore.new }

      def cache_metrics(&)
        semantic_logger_metrics(&).select { |metric| metric.name == "rails.cache.operation.duration" }
      end

      it "records a read miss and a read hit" do
        metrics = cache_metrics do
          store.read("missing")
          store.write("present", 1)
          store.read("present")
        end

        assert_metric(
          metrics,
          name:       "rails.cache.operation.duration",
          kind:       :histogram,
          unit:       "s",
          dimensions: {
            "rails.cache.operation.name" => "read",
            "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore",
            "rails.cache.hit"            => false
          }
        )
        assert_metric(metrics, name: "rails.cache.operation.duration", dimensions: {
                        "rails.cache.operation.name" => "read",
                        "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore",
                        "rails.cache.hit"            => true
                      })
        assert_metric(metrics, name: "rails.cache.operation.duration", dimensions: {
                        "rails.cache.operation.name" => "write",
                        "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore"
                      })
      end

      it "records each step of a fetch" do
        generate   = proc { 1 }
        metrics    = cache_metrics { store.fetch("key", &generate) }
        operations = metrics.map { |metric| metric.dimensions["rails.cache.operation.name"] }

        assert_includes operations, "generate"
        assert_includes operations, "write"
      end

      it "records a fetch that hit, and its read" do
        store.write("key", 1)
        generate = proc { 2 }
        metrics  = cache_metrics { store.fetch("key", &generate) }

        assert_metric(metrics, name: "rails.cache.operation.duration", dimensions: {
                        "rails.cache.operation.name" => "fetch_hit",
                        "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore"
                      })
        assert_metric(metrics, name: "rails.cache.operation.duration", dimensions: {
                        "rails.cache.operation.name" => "read",
                        "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore",
                        "rails.cache.hit"            => true
                      })
      end

      it "names exist? without its question mark" do
        metrics = cache_metrics { store.exist?("key") }

        assert_metric(metrics, name: "rails.cache.operation.duration", dimensions: {
                        "rails.cache.operation.name" => "exist",
                        "rails.cache.store"          => "ActiveSupport::Cache::MemoryStore"
                      })
      end
    end
  end
end
