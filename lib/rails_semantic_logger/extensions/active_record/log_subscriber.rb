ActiveRecord::LogSubscriber
module ActiveRecord
  class LogSubscriber
    def sql(event)
      self.class.runtime += event.duration

      return unless logger.debug?

      payload = event.payload
      name    = payload[:name]
      return if ['SCHEMA', 'EXPLAIN'].include?(name)

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
        if Rails::VERSION::MAJOR == 5 && Rails::VERSION::MINOR == 0 && Rails::VERSION::TINY <= 2
          payload[:binds].each do |attr|
            attr_name, value = render_bind(attr)
            binds[attr_name] = value
          end
        elsif Rails::VERSION::MAJOR >= 5
          casted_params = type_casted_binds(payload[:binds], payload[:type_casted_binds])
          payload[:binds].zip(casted_params).map { |attr, value|
            render_bind(attr, value)
          }
        else
          payload[:binds].each do |col, v|
            attr_name, value = render_bind(col, v)
            binds[attr_name] = value
          end
        end
      end
      debug(log)
    end

  end
end
