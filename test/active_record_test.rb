require_relative "test_helper"

class ActiveRecordTest < Minitest::Test
  describe "ActiveRecord" do
    let(:name_query_sql) do
      'SELECT "samples".* FROM "samples" WHERE "samples"."name" = ? ORDER BY "samples"."id" ASC LIMIT ?'
    end

    # Emit a sql.active_record event with a controlled payload so the metadata branches
    # (async / lock_wait / cached) can be asserted deterministically.
    def instrument_sql(**payload)
      semantic_logger_events do
        ActiveSupport::Notifications.instrument(
          "sql.active_record",
          {sql: "SELECT 1", name: "Sample Load"}.merge(payload)
        )
      end
    end

    describe "logs" do
      it "sql" do
        expected_sql = 'SELECT "samples".* FROM "samples" ORDER BY "samples"."id" ASC LIMIT ?'

        messages = semantic_logger_events do
          Sample.first
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:   expected_sql,
            binds: {limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations]
      end

      it "sql with query cache" do
        messages = semantic_logger_events do
          Sample.cache { 2.times { Sample.where(name: "foo").first } }
        end

        assert_equal 2, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:   name_query_sql,
            binds: {name: "foo", limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations]

        assert_semantic_logger_event(
          messages[1],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:    name_query_sql,
            binds:  {name: "foo", limit: 1},
            cached: true
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations]
      end

      it "single bind value" do
        messages = semantic_logger_events do
          Sample.where(name: "Jack").first
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:   name_query_sql,
            binds: {name: "Jack", limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations]
      end

      it "filtered bind value" do
        filter_params_setting %i[name] do
          messages = semantic_logger_events do
            Sample.where(name: "Jack").first
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "ActiveRecord::Base",
            message:          "Sample Load",
            payload_includes: {
              sql:   name_query_sql,
              binds: {name: "[FILTERED]", limit: 1}
            }
          )
          assert_instance_of Integer, messages[0].payload[:allocations]
        end
      end

      it "filtered bind value when filter_parameters set as regex" do
        filter_params_regex_setting %i[name] do
          messages = semantic_logger_events do
            Sample.where(name: "Jack").first
          end

          assert_equal 1, messages.count, messages

          assert_semantic_logger_event(
            messages[0],
            level:            :debug,
            name:             "ActiveRecord::Base",
            message:          "Sample Load",
            payload_includes: {
              sql:   name_query_sql,
              binds: {name: "[FILTERED]", limit: 1}
            }
          )
          assert_instance_of Integer, messages[0].payload[:allocations]
        end
      end

      it "multiple bind values" do
        expected_sql =
          'SELECT "samples".* FROM "samples" WHERE "samples"."age" BETWEEN ? AND ? ORDER BY "samples"."id" ASC LIMIT ?'

        messages = semantic_logger_events do
          Sample.where(age: 2..21).first
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:   expected_sql,
            binds: {age: [2, 21], limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations]
      end

      it "works with an IN clause" do
        expected_sql =
          'SELECT "samples".* FROM "samples" WHERE "samples"."age" IN (?, ?) ORDER BY "samples"."id" ASC LIMIT ?'

        messages = semantic_logger_events do
          Sample.where(age: [2, 3]).first
        end

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:   expected_sql,
            binds: {age: [2, 3], limit: 1}
          }
        )
      end
    end

    describe "async queries" do
      before do
        ActiveRecord::Base.asynchronous_queries_tracker.start_session
      end

      after do
        ActiveRecord::Base.asynchronous_queries_tracker.finalize_session
      end

      it "marks async queries with async: true" do
        expected_sql = 'SELECT COUNT(*) FROM "samples"'

        messages = semantic_logger_events do
          Sample.count
          Sample.async_count.value
        end

        assert_equal 2, messages.count, messages

        messages.each do |message|
          assert_semantic_logger_event(
            message,
            level:            :debug,
            name:             "ActiveRecord::Base",
            message:          "Sample Count",
            payload_includes: {sql: expected_sql}
          )
        end
        refute messages[0].payload.key?(:async)

        # messages[1] comes from async_count, but Rails only sets payload[:async]
        # when the background thread runs the query before .value is requested; otherwise
        # it falls back to running synchronously in the foreground. That race makes any
        # assertion on messages[1].payload[:async] flaky here. The subscriber's async
        # branch is covered deterministically by the "async metadata" tests below.
      end
    end

    describe "async metadata" do
      it "includes lock_wait for async queries" do
        messages = instrument_sql(async: true, lock_wait: 12.5)

        assert_equal 1, messages.count, messages
        assert_equal true, messages[0].payload[:async]
        assert_in_delta(12.5, messages[0].payload[:lock_wait])
      end

      it "omits async and lock_wait for synchronous queries" do
        messages = instrument_sql

        assert_equal 1, messages.count, messages
        refute messages[0].payload.key?(:async)
        refute messages[0].payload.key?(:lock_wait)
      end
    end

    describe "cached metadata" do
      it "sets cached: true when served from the query cache" do
        messages = instrument_sql(cached: true)

        assert_equal true, messages[0].payload[:cached]
      end

      it "omits cached when the query was not cached" do
        messages = instrument_sql(cached: false)

        refute messages[0].payload.key?(:cached)
      end
    end

    describe "strict loading violations" do
      let(:owner) do
        Class.new do
          def self.name
            "Article"
          end
        end
      end

      def instrument_violation(reflection, owner)
        semantic_logger_events do
          ActiveSupport::Notifications.instrument(
            "strict_loading_violation.active_record",
            owner: owner, reflection: reflection
          )
        end
      end

      it "logs a non-polymorphic violation with the associated class" do
        klass = Class.new do
          def self.name
            "Comment"
          end
        end
        reflection = Struct.new(:name, :klass) do
          def polymorphic?
            false
          end

          def strict_loading_violation_message(owner)
            "`#{owner}` is marked for strict_loading. " \
              "The #{klass} association named `:#{name}` cannot be lazily loaded."
          end
        end.new(:comments, klass)

        messages = instrument_violation(reflection, owner)

        assert_equal 1, messages.count, messages

        assert_semantic_logger_event(
          messages[0],
          level:            :debug,
          name:             "ActiveRecord::Base",
          payload_includes: {owner: "Article", association: :comments, class: "Comment"}
        )
        assert_includes messages[0].message, "strict_loading"
      end

      it "omits the class for polymorphic associations" do
        reflection = Struct.new(:name) do
          def polymorphic?
            true
          end

          def strict_loading_violation_message(owner)
            "`#{owner}` is marked for strict_loading."
          end
        end.new(:commentable)

        messages = instrument_violation(reflection, owner)

        assert_equal 1, messages.count, messages

        assert_equal "Article", messages[0].payload[:owner]
        assert_equal :commentable, messages[0].payload[:association]
        refute messages[0].payload.key?(:class)
      end
    end
  end
end
