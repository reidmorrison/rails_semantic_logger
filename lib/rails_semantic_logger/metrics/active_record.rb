module RailsSemanticLogger
  module Metrics
    # Records each query that Active Record sends to its database as `db.client.operation.duration`,
    # OpenTelemetry's stable database client metric, in seconds. It leaves out the queries that never
    # reach the database (served from the query cache) and those that Rails runs to read the schema.
    class ActiveRecord < Subscriber
      NAME = "db.client.operation.duration".freeze

      # Rails' names for the queries it runs to read the schema.
      IGNORE_NAMES = %w[SCHEMA].freeze

      # OpenTelemetry's db.system.name for each adapter that Rails ships, by its adapter_name. Any
      # other adapter is named by its adapter_name, in lowercase.
      SYSTEM_NAMES = {
        "PostgreSQL" => "postgresql",
        "PostGIS"    => "postgresql",
        "Mysql2"     => "mysql",
        "Trilogy"    => "mysql",
        "SQLite"     => "sqlite"
      }.freeze

      # Comments that Rails' query log tags, or the application, put before the statement.
      LEADING_COMMENTS = %r{\A\s*(?:/\*.*?\*/\s*)*}m

      def sql(event)
        payload = event.payload
        return if payload[:cached] || IGNORE_NAMES.include?(payload[:name])

        time(NAME, event, dimensions(payload))
      end

      private

      def dimensions(payload)
        dimensions = {}
        connection = payload[:connection]
        if connection
          dimensions["db.system.name"] = system_name(connection.adapter_name)
          namespace                    = namespace(connection)
          dimensions["db.namespace"]   = namespace if namespace
        end
        operation = operation(payload[:sql])
        dimensions["db.operation.name"] = operation if operation
        dimensions["rails.active_record.query.name"] = payload[:name] if payload[:name]
        dimensions["error.type"] = payload[:exception].first if payload[:exception]
        dimensions
      end

      def system_name(adapter_name)
        SYSTEM_NAMES.fetch(adapter_name) { adapter_name.downcase }
      end

      # The database, as the application's database configuration names it.
      def namespace(connection)
        connection.pool.db_config.database&.to_s
      rescue StandardError
        nil
      end

      # The statement's leading keyword, such as SELECT or BEGIN, for a single statement only: the
      # conventions name no single operation for several.
      def operation(sql)
        return unless sql.is_a?(String)

        statement = sql.sub(LEADING_COMMENTS, "")
        return if statement.rstrip.chomp(";").include?(";")

        statement[/\A\w+/]&.upcase
      end
    end
  end
end
