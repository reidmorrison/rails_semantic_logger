require_relative "../test_helper"

module Metrics
  class MetricsTest < Minitest::Test
    describe RailsSemanticLogger::Metrics do
      it "declares the dimension keys of every recorder safe from the sensitive keys" do
        safe = SemanticLogger.safe_dimension_keys

        RailsSemanticLogger::Metrics.dimension_keys.each { |key| assert_includes safe, key }
        assert_includes safe, "messaging.destination.name"
        assert_includes safe, "http.route"
      end

      it "keeps a dimension key that a sensitive key matches" do
        original = SemanticLogger.sensitive_keys
        SemanticLogger.sensitive_keys = %i[name type]
        redactor = SemanticLogger::Metric::DimensionRedactor.new(SemanticLogger.redactor)

        assert_nil redactor.replacement_for("messaging.destination.name")
        assert_nil redactor.replacement_for("error.type")
        assert redactor.replacement_for("customer.name"), "an undeclared sensitive key was not redacted"
      ensure
        SemanticLogger.sensitive_keys = original
      end
    end
  end
end
