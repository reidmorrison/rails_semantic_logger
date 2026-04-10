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
            name:             "ActiveRecord",
            message:          "Sample Count",
            payload_includes: {sql: expected_sql}
          )
        end

        # On Rails prior to 8.0.2, these assertions will mostly pass, but not always.
        # https://github.com/rails/rails/pull/54344
        skip "Older Rails has flakey async instrumentation" if Rails.version < Gem::Version.new("8.0.2")
        refute messages[0].payload.key?(:async)
        assert_equal true, messages[1].payload[:async]
      end
    end

    # we could feasibly pull this back to rails 7.1.  This update is related to rails 8.1
    # https://github.com/reidmorrison/rails_semantic_logger/pull/276#issuecomment-3533151110
    describe "runtime=" do
      gem_version = RailsSemanticLogger::ActiveRecord::LogSubscriber::RAILS_VERSION_ENDING_SET_RUNTIME_SUPPORT
      it "older versions of rails than #{gem_version} allow reads and writes to the runtime" do
        skip "We only set runtime on rails versions older than #{gem_version}" if Rails.version >= gem_version
        RailsSemanticLogger::ActiveRecord::LogSubscriber.runtime = 5.0

        assert_equal RailsSemanticLogger::ActiveRecord::LogSubscriber.runtime, 5.0
      end

      it "starting with rails #{gem_version} and later we do not write to the runtime" do
        skip "We skip setting runtime on rails versions equal or newer than #{gem_version}" if Rails.version < gem_version

        initial_value = RailsSemanticLogger::ActiveRecord::LogSubscriber.runtime
        RailsSemanticLogger::ActiveRecord::LogSubscriber.runtime = initial_value + 5000.0
        assert_equal RailsSemanticLogger::ActiveRecord::LogSubscriber.runtime, initial_value
      end
    end
  end
end
