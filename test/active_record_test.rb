require_relative "test_helper"

class ActiveRecordTest < Minitest::Test
  describe "ActiveRecord" do
    # Rails 5 has an extra space
    let(:extra_space) { Rails::VERSION::MAJOR >= 6 ? "" : " " }

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
          name:             "ActiveRecord",
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
          name:             "ActiveRecord",
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
          name:             "ActiveRecord",
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
          name:             "ActiveRecord",
          message:          "Sample Load",
          payload_includes: {
            sql:   expected_sql,
            binds: {name: "Jack", limit: 1}
          }
        )
        assert_instance_of Integer, messages[0].payload[:allocations] if Rails.version.to_i >= 6
      end

      it "filtered bind value" do
        filter_params_setting true, %i[name] do
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
            name:             "ActiveRecord",
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
        filter_params_regex_setting true, %i[name] do
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
            name:             "ActiveRecord",
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
          name:             "ActiveRecord",
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
          name:             "ActiveRecord",
          message:          "Sample Load",
          payload_includes: {
            sql:   expected_sql,
            binds: {age: [2, 3], limit: 1}
          }
        )
      end

      it "marks async queries with async: true" do
        skip "Not applicable to older rails" if Rails.version.to_f < 7.1
        skip "TODO: Fails on Rails 8 because of a missing session." if Rails.version.to_i >= 8

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
            name:             "ActiveRecord",
            message:          "Sample Count",
            payload_includes: {sql: expected_sql}
          )
        end
        refute messages[0].payload.key?(:async)
        assert_equal true, messages[1].payload[:async]
      end
    end
  end
end
