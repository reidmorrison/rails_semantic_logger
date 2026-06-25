require_relative "test_helper"

class ActiveRecordTest < Minitest::Test
  describe "ActiveRecord" do
    # Rails 5 has an extra space
    let(:extra_space) { Rails::VERSION::MAJOR >= 6 ? "" : " " }

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
        expected_sql = "SELECT #{extra_space}\"samples\".* FROM \"samples\" ORDER BY \"samples\".\"id\" ASC LIMIT ?"

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
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
      end

      it "sql with query cache" do
        expected_sql = "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"

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
            sql:   expected_sql,
            binds: {name: "foo", limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6

        assert_semantic_logger_event(
          messages[1],
          level:            :debug,
          name:             "ActiveRecord::Base",
          message:          "Sample Load",
          payload_includes: {
            sql:    expected_sql,
            binds:  {name: "foo", limit: 1},
            cached: true
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
      end

      it "single bind value" do
        expected_sql =
          if Rails.version.to_f >= 5.2
            "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
          else
            "SELECT  \"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
          end

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
            sql:   expected_sql,
            binds: {name: "Jack", limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
      end

      it "filtered bind value" do
        filter_params_setting %i[name] do
          expected_sql =
            if Rails.version.to_f >= 5.2
              "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
            else
              "SELECT  \"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
            end

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
              sql:   expected_sql,
              binds: {name: "[FILTERED]", limit: 1}
            }
          )
          assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
        end
      end

      it "filtered bind value when filter_parameters set as regex" do
        filter_params_regex_setting %i[name] do
          expected_sql =
            if Rails.version.to_f >= 5.2
              "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
            else
              "SELECT  \"samples\".* FROM \"samples\" WHERE \"samples\".\"name\" = ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"
            end

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
              sql:   expected_sql,
              binds: {name: "[FILTERED]", limit: 1}
            }
          )
          assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
        end
      end

      it "multiple bind values" do
        skip "Not applicable to older rails" if Rails.version.to_f <= 5.1

        expected_sql = "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"age\" BETWEEN ? AND ? ORDER BY \"samples\".\"id\" ASC LIMIT ?"

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
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
      end

      it "works with an IN clause" do
        skip "Not applicable to older rails" if Rails.version.to_f <= 5.1

        expected_sql = "SELECT #{extra_space}\"samples\".* FROM \"samples\" WHERE \"samples\".\"age\" IN (?, ?) ORDER BY \"samples\".\"id\" ASC LIMIT ?"

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
        skip "Not applicable to older rails" if Rails.version.to_f < 7.1
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

        # TODO: This test is flaky and needs to be fixed.
        # assert_equal true, messages[1].payload[:async]
      end
    end

    describe "async metadata" do
      it "includes lock_wait for async queries" do
        messages = instrument_sql(async: true, lock_wait: 12.5)
        assert_equal 1, messages.count, messages
        assert_equal true, messages[0].payload[:async]
        assert_equal 12.5, messages[0].payload[:lock_wait]
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
