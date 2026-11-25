module RailsSemanticLogger
  module Metrics
    # Records each query that Active Record sends to its database as `db.client.operation.duration`,
    # OpenTelemetry's stable database client metric, in seconds. It leaves out the queries that never
    # reach the database (served from the query cache) and those that Rails runs to read the schema.
    class ActiveRecord < Subscriber
      # The logger of Active Record, whose name is the meter of its metrics.
      LOGGER_NAME = "ActiveRecord::Base".freeze

      # The dimensions it records, which no sensitive key redacts (see Metrics.declare_dimension_keys).
      DIMENSION_KEYS = %w[db.system.name db.namespace db.operation.name error.type].freeze

      NAME = "db.client.operation.duration".freeze

      # Rails' names for the queries it runs to read the schema or explain a query, as its own log
      # subscriber leaves out.
      IGNORE_NAMES = %w[SCHEMA EXPLAIN].freeze

      # OpenTelemetry's db.system.name for each adapter that Rails ships, by its adapter_name. Any
      # other adapter is named by its adapter_name, in lowercase.
      SYSTEM_NAMES = {
        "PostgreSQL"     => "postgresql",
        "PostGIS"        => "postgresql",
        "Mysql2"         => "mysql",
        "Trilogy"        => "mysql",
        "SQLite"         => "sqlite",
        "SQLServer"      => "microsoft.sql_server",
        "OracleEnhanced" => "oracle.db"
      }.freeze

      # Comments that Rails' query log tags, or the application, put before the statement.
      LEADING_COMMENTS = %r{\A\s*(?:(?:/\*.*?\*/|--[^\n]*)\s*)*}m

      # String literals and comments, which can hold a semicolon that does not end the statement, such as
      # the query log tags that Rails appends. One pattern, so that whichever starts first wins: an
      # apostrophe in a comment is not a literal. A literal takes the '' escape of the standard and the
      # \' escape of MySQL, so on PostgreSQL and SQLite a literal that ends in a backslash is misread,
      # and the statement is then recorded without an operation.
      LITERALS_AND_COMMENTS = %r{'(?:[^'\\]|\\.|'')*'|/\*.*?\*/|--[^\n]*}m

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
          dimensions["db.system.name"] = system_name(connection)
          namespace                    = namespace(connection)
          dimensions["db.namespace"]   = namespace if namespace
        end
        operation = operation(payload[:sql])
        dimensions["db.operation.name"] = operation if operation
        failure                  = raised_error_type(payload)
        dimensions["error.type"] = failure if failure
        dimensions
      end

      # MariaDB shares MySQL's adapters, which tell them apart.
      def system_name(connection)
        return "mariadb" if connection.respond_to?(:mariadb?) && connection.mariadb?

        adapter_name = connection.adapter_name
        SYSTEM_NAMES.fetch(adapter_name) { adapter_name.downcase }
      end

      # The database, as the application's database configuration names it. A SQLite database is a
      # file: it is named without its directory, which differs per deployment.
      def namespace(connection)
        database = connection.pool.db_config.database&.to_s
        return database unless database && connection.adapter_name == "SQLite"

        File.basename(database, ".*")
      rescue StandardError
        nil
      end

      # The statement's leading keyword, such as SELECT or BEGIN, for a single statement only: the
      # conventions name no single operation for several.
      def operation(sql)
        return unless sql.is_a?(String) && sql.valid_encoding?

        statement = sql.sub(LEADING_COMMENTS, "")
        return if several_statements?(statement)

        statement[/\A\w+/]&.upcase
      end

      # Whether the SQL holds more than one statement: a semicolon with more SQL after it, outside any
      # string literal or comment. Only SQL with a semicolon is scanned, since a bulk insert can be large.
      def several_statements?(statement)
        return false unless statement.include?(";")

        statement.gsub(LITERALS_AND_COMMENTS, "").rstrip.chomp(";").include?(";")
      end
    end
  end
end
