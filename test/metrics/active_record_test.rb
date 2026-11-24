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
        assert_equal "test", metric.dimensions["db.namespace"]
        refute metric.dimensions.key?("rails.active_record.query.name")
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

      it "never fails a query whose SQL is not valid UTF-8" do
        sql = "SELECT * FROM samples WHERE name = '\xff'".dup.force_encoding("UTF-8")

        metrics = db_metrics(semantic_logger_metrics { Sample.connection.select_all(sql) })

        refute assert_metric(metrics, name: "db.client.operation.duration").dimensions.key?("db.operation.name")
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

        it "is the keyword after a line comment" do
          assert_equal "SELECT", operation("-- report\nSELECT 1")
        end

        it "is the keyword of one statement with a semicolon in a string" do
          assert_equal "INSERT", operation("INSERT INTO notes (body) VALUES ('a; b')")
        end

        it "is the keyword of one statement with a semicolon in a MySQL escaped string or a trailing comment" do
          assert_equal "INSERT", operation("INSERT INTO t VALUES ('a\\'; b')")
          assert_equal "SELECT", operation("SELECT 1 /* a; b */")
          assert_equal "SELECT", operation("SELECT 1; -- done")
        end

        it "reads an apostrophe in a comment as part of the comment" do
          assert_equal "SELECT", operation("SELECT 1 /* it's */, 'a;b'")
          assert_nil operation("SELECT 1 -- it's\n; DELETE FROM t WHERE a = 'x'")
        end

        it "is nil for SQL that is not valid UTF-8" do
          assert_nil operation("SELECT '\xff'".dup.force_encoding("UTF-8"))
        end

        it "is the keyword of one statement that ends with a semicolon" do
          assert_equal "DELETE", operation("DELETE FROM samples;")
        end
      end
    end
  end
end
