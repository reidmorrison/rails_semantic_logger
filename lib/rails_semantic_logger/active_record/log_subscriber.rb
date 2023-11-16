module RailsSemanticLogger
  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      IGNORE_PAYLOAD_NAMES = %w[SCHEMA EXPLAIN].freeze

      class << self
        attr_reader :logger
      end

      def self.runtime=(value)
        ::ActiveRecord::RuntimeRegistry.sql_runtime = value
      end

      def self.runtime
        ::ActiveRecord::RuntimeRegistry.sql_runtime ||= 0
      end

      def self.reset_runtime
        rt           = runtime
        self.runtime = 0
        rt
      end

      def sql(event)
        self.class.runtime += event.duration
        return unless logger.debug?

        payload = event.payload
        name    = payload[:name]
        return if IGNORE_PAYLOAD_NAMES.include?(name)

        log_payload         = {sql: payload[:sql]}
        log_payload[:binds] = bind_values(payload) unless (payload[:binds] || []).empty?
        log_payload[:allocations] = event.allocations if event.respond_to?(:allocations)
        log_payload[:cached] = event.payload[:cached]

        log = {
          message:  name,
          payload:  log_payload,
          duration: event.duration
        }

        # Log the location of the query itself.
        if logger.send(:level_index) >= SemanticLogger.backtrace_level_index
          log[:backtrace] = SemanticLogger::Utils.strip_backtrace(caller)
        end

        logger.debug(log)
      end

      private

      @logger = SemanticLogger["ActiveRecord"]

      # When multiple values are received for a single bound field, it is converted into an array
      def add_bind_value(binds, key, value)
        key        = key.downcase.to_sym unless key.nil?
        value      = (Array(binds[key]) << value) if binds.key?(key)
        binds[key] = value
      end

      def logger
        self.class.logger
      end

      #
      # Rails 3,4,5 hell trying to get the bind values
      #

      def bind_values_v3(payload)
        binds = {}
        payload[:binds].each do |col, v|
          if col
            add_bind_value(binds, col.name, v)
          else
            binds[nil] = v
          end
        end
        binds
      end

      def bind_values_v4(payload)
        binds = {}
        payload[:binds].each do |col, v|
          attr_name, value = render_bind(col, v)
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def bind_values_v5_0_0(payload)
        binds = {}
        payload[:binds].each do |attr|
          attr_name, value = render_bind(attr)
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def bind_values_v5_0_3(payload)
        binds         = {}
        casted_params = type_casted_binds(payload[:binds], payload[:type_casted_binds])
        payload[:binds].zip(casted_params).map do |attr, value|
          attr_name, value = render_bind(attr, value)
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def bind_values_v5_1_5(payload)
        binds         = {}
        casted_params = type_casted_binds(payload[:type_casted_binds])
        payload[:binds].zip(casted_params).map do |attr, value|
          attr_name, value = render_bind(attr, value)
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def bind_values_v6_1(payload)
        binds         = {}
        casted_params = type_casted_binds(payload[:type_casted_binds])
        payload[:binds].each_with_index do |attr, i|
          attr_name, value = render_bind(attr, casted_params[i])
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def render_bind_v4_2(column, value)
        if column
          if column.binary?
            # This specifically deals with the PG adapter that casts bytea columns into a Hash.
            value = value[:value] if value.is_a?(Hash)
            value = value ? "<#{value.bytesize} bytes of binary data>" : "<NULL binary data>"
          end

          [column.name, value]
        else
          [nil, value]
        end
      end

      def render_bind_v5_0_0(attribute)
        value =
          if attribute.type.binary? && attribute.value
            if attribute.value.is_a?(Hash)
              "<#{attribute.value_for_database.to_s.bytesize} bytes of binary data>"
            else
              "<#{attribute.value.bytesize} bytes of binary data>"
            end
          else
            attribute.value_for_database
          end

        [attribute.name, value]
      end

      def render_bind_v5_0_3(attr, value)
        if attr.is_a?(Array)
          attr = attr.first
        elsif attr.type.binary? && attr.value
          value = "<#{attr.value_for_database.to_s.bytesize} bytes of binary data>"
        end

        [attr&.name, value]
      end

      def render_bind_v6_1(attr, value)
        case attr
        when ActiveModel::Attribute
          value = "<#{attr.value_for_database.to_s.bytesize} bytes of binary data>" if attr.type.binary? && attr.value
        when Array
          attr = attr.first
        else
          attr = nil
        end

        [attr&.name || :nil, value]
      end

      def type_casted_binds_v5_0_3(binds, casted_binds)
        casted_binds || ::ActiveRecord::Base.connection.type_casted_binds(binds)
      end

      def type_casted_binds_v5_1_5(casted_binds)
        casted_binds.respond_to?(:call) ? casted_binds.call : casted_binds
      end

      if Rails::VERSION::MAJOR == 5 && Rails::VERSION::MINOR.zero? && Rails::VERSION::TINY <= 2 # 5.0.0 - 5.0.2
        alias bind_values bind_values_v5_0_0
        alias render_bind render_bind_v5_0_0
      elsif Rails::VERSION::MAJOR == 5 &&
            ((Rails::VERSION::MINOR.zero? && Rails::VERSION::TINY <= 6) ||
              (Rails::VERSION::MINOR == 1 && Rails::VERSION::TINY <= 4)) # 5.0.3 - 5.0.6 && 5.1.0 - 5.1.4
        alias bind_values bind_values_v5_0_3
        alias render_bind render_bind_v5_0_3
        alias type_casted_binds type_casted_binds_v5_0_3
      elsif (Rails::VERSION::MAJOR == 6 && Rails::VERSION::MINOR > 0) || # ~> 6.1.0
            Rails::VERSION::MAJOR == 7
        alias bind_values bind_values_v6_1
        alias render_bind render_bind_v6_1
        alias type_casted_binds type_casted_binds_v5_1_5
      elsif Rails::VERSION::MAJOR >= 5 # ~> 5.1.5 && ~> 5.0.7 && 6.x.x
        alias bind_values bind_values_v5_1_5
        alias render_bind render_bind_v5_0_3
        alias type_casted_binds type_casted_binds_v5_1_5
      elsif Rails.version.to_i >= 4 # 4.x
        alias bind_values bind_values_v4
        alias render_bind render_bind_v4_2
      else # 3.x
        alias bind_values bind_values_v3
      end
    end
  end
end
