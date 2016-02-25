ActiveRecord::LogSubscriber
module ActiveRecord
  class LogSubscriber
    def sql(event)
      self.class.runtime += event.duration

      return unless logger.debug?

      payload = event.payload
      name    = payload[:name]
      return if IGNORE_PAYLOAD_NAMES.include?(name)

      log = {
        message:  name,
        sql:      payload[:sql],
        duration: event.duration
      }
      unless (payload[:binds] || []).empty?
        log[:binds] = binds = {}
        # Changed with Rails 5
        if Rails.version.to_i >= 5
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
