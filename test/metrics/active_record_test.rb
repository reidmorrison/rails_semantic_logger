require_relative "../test_helper"

module Metrics
  class ActiveRecordTest < Minitest::Test
    describe RailsSemanticLogger::Metrics::ActiveRecord do
      def db_metrics(metrics)
        metrics.select { |metric| metric.name == "db.client.operation.duration" }
      end

      it "records a query with the system, database, operation and query name" do
        metrics = db_metrics(semantic_logger_metrics { Sample.where(name: "x").to_a })

        metric = assert_metric(metrics, name: "db.client.operation.duration", kind: :histogram, unit: "s")

        assert_equal "sqlite", metric.dimensions["db.system.name"]
        assert_equal "SELECT", metric.dimensions["db.operation.name"]
        assert_equal "Sample Load", metric.dimensions["rails.active_record.query.name"]
        assert_match(/test/, metric.dimensions["db.namespace"])
      end

      it "leaves out queries served from the query cache" do
        metrics = semantic_logger_metrics do
          Sample.cache do
            Sample.where(name: "x").to_a
            Sample.where(name: "x").to_a
          end
        end

        assert_equal 1, db_metrics(metrics).size, metrics.map(&:to_h)
      end

      it "records the error.type of a query that failed" do
        metrics = semantic_logger_metrics do
          assert_raises(ActiveRecord::StatementInvalid) { Sample.connection.select_all("SELECT * FROM missing_table") }
        end

        metric = assert_metric(db_metrics(metrics), name: "db.client.operation.duration")

        assert_equal "ActiveRecord::StatementInvalid", metric.dimensions["error.type"]
      end

      describe "operation" do
        let(:subscriber) { RailsSemanticLogger::Metrics::ActiveRecord.new }

        def operation(sql) = subscriber.send(:operation, sql)

        it "is the leading keyword, after any comments" do
          assert_equal "SELECT", operation("/*application:Dummy*/ select 1")
          assert_equal "BEGIN", operation("BEGIN")
        end

        it "is nil for several statements" do
          assert_nil operation("SELECT 1; SELECT 2")
        end

        it "is the keyword of one statement that ends with a semicolon" do
          assert_equal "DELETE", operation("DELETE FROM samples;")
        end
      end
    end
  end
end
