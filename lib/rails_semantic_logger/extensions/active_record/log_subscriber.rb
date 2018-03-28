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
        log_payload[:binds] = binds = {}
        if Rails::VERSION::MAJOR == 5 && Rails::VERSION::MINOR == 0 && Rails::VERSION::TINY <= 2 # 5.0.0 - 5.0.2
          payload[:binds].each do |attr|
            attr_name, value = render_bind(attr)
            binds[attr_name] = value
          end
        elsif Rails::VERSION::MAJOR >= 5 && Rails::VERSION::MINOR <= 1 && (Rails::VERSION::MINOR == 0 || Rails::VERSION::TINY <= 4) # 5.0.3 - 5.1.4
          casted_params = type_casted_binds(payload[:binds], payload[:type_casted_binds])
          payload[:binds].zip(casted_params).map { |attr, value|
            attr_name, value = render_bind(attr, value)
            binds[attr_name] = value
          }
        elsif Rails::VERSION::MAJOR >= 5 # >= 5.1.5
          casted_params = type_casted_binds(payload[:type_casted_binds])
          payload[:binds].zip(casted_params).map do |attr, value|
            render_bind(attr, value)
          end
        elsif Rails.version.to_i >= 4 # 4.x
          payload[:binds].each do |col, v|
            attr_name, value = render_bind(col, v)
            binds[attr_name] = value
          end
        else # 3.x
          payload[:binds].each do |col,v|
            if col
              binds[col.name] = v
            else
              binds[nil] = v
            end
          end
        end
      end
      debug(log)
    end

  end
end
