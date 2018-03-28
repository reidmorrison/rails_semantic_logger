ActiveRecord::LogSubscriber
module ActiveRecord
  class LogSubscriber
    # Support Rails 3.2
    IGNORE_PAYLOAD_NAMES = ['SCHEMA', 'EXPLAIN'] unless defined?(IGNORE_PAYLOAD_NAMES)

    def sql(event)
      self.class.runtime += event.duration

      return unless logger.debug?

      payload = event.payload
      name    = payload[:name]
      return if IGNORE_PAYLOAD_NAMES.include?(name)

      log_payload = {
        sql: payload[:sql],
      }
      log         = {
        message:  name,
        payload:  log_payload,
        duration: event.duration
      }

      unless (payload[:binds] || []).empty?
        log_payload[:binds] =
          if Rails::VERSION::MAJOR == 5 && Rails::VERSION::MINOR == 0 && Rails::VERSION::TINY <= 2 # 5.0.0 - 5.0.2
            bind_values_v5_0_0(payload)
          elsif Rails::VERSION::MAJOR >= 5 && Rails::VERSION::MINOR <= 1 && (Rails::VERSION::MINOR == 0 || Rails::VERSION::TINY <= 4) # 5.0.3 - 5.1.4
            bind_values_v5_0_3(payload)
          elsif Rails::VERSION::MAJOR >= 5 # >= 5.1.5
            bind_values_v5_1_5(payload)
          elsif Rails.version.to_i >= 4 # 4.x
            bind_values_v4(payload)
          else # 3.x
            bind_values_v3(payload)
          end
      end
      debug(log)
    end

    private

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

    # When multiple values are received for a single bound field, it is converted into an array
    def add_bind_value(binds, key, value)
      key        = key.downcase.to_sym
      value      = (Array(binds[key]) << value) if binds.key?(key)
      binds[key] = value
    end

  end
end
