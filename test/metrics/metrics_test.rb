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

      it "records each component's metrics through the component's own logger, named after it" do
        loggers = {
          RailsSemanticLogger::Metrics::ActionController => ::ActionController::Base.logger,
          RailsSemanticLogger::Metrics::ActionView       => ::ActionView::Base.logger,
          RailsSemanticLogger::Metrics::ActiveRecord     => ::ActiveRecord::Base.logger,
          RailsSemanticLogger::Metrics::ActiveJob        => ::ActiveJob::Base.logger,
          RailsSemanticLogger::Metrics::ActionMailer     => ::ActionMailer::Base.logger,
          RailsSemanticLogger::Metrics::Cache            => ::ActiveSupport::Cache::Store.logger
        }
        loggers[RailsSemanticLogger::Metrics::SolidQueue] = ::SolidQueue.logger if defined?(::SolidQueue)

        loggers.each do |subscriber, logger|
          assert_same logger, subscriber.logger, subscriber.name
        end
        assert_equal %w[ActionController::Base ActionView::Base ActiveRecord::Base ActiveJob::Base ActionMailer::Base
                        ActiveSupport::Cache::Store],
                     loggers.values.first(6).map(&:name)
      end

      it "attaches every subscriber, and Solid Queue's only when told to" do
        attached = []
        stubbed  = []
        RailsSemanticLogger::Metrics::SUBSCRIBERS.each_key do |name|
          subscriber = RailsSemanticLogger::Metrics.const_get(name)
          subscriber.define_singleton_method(:attach_to) { |namespace| attached << [name, namespace] }
          stubbed << subscriber
        end

        RailsSemanticLogger::Metrics.attach(solid_queue: false)

        assert_equal RailsSemanticLogger::Metrics::SUBSCRIBERS.except("SolidQueue").to_a, attached

        attached.clear
        RailsSemanticLogger::Metrics.attach

        assert_equal RailsSemanticLogger::Metrics::SUBSCRIBERS.to_a, attached
      ensure
        stubbed.each { |subscriber| subscriber.singleton_class.send(:remove_method, :attach_to) }
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
