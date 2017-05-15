ActiveRecord::LogSubscriber
module ActiveRecord
  class LogSubscriber
    def sql(event)
      self.class.runtime += event.duration

      return unless logger.debug?

      payload = event.payload
      name    = payload[:name]
      return if IGNORE_PAYLOAD_NAMES.include?(name)

      log_payload = {
        sql:      payload[:sql],
      }
      log = {
        message:  name,
        payload:  log_payload,
        duration: event.duration
      }
      unless (payload[:binds] || []).empty?
        log_payload[:binds] = binds = {}
        if Rails.version >= "5.0.3"
          casted_params = type_casted_binds(payload[:binds], payload[:type_casted_binds])
          payload[:binds].zip(casted_params).map { |attr, value|
            render_bind(attr, value)
          }
        elsif Rails.version >= "5.0.0"
          payload[:binds].each do |attr|
            attr_name, value = render_bind(attr)
            binds[attr_name] = value
          end
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
