# This subscriber is a reimplementation of Rails' own ActiveRecord::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/activerecord/lib/active_record/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/activerecord/lib/active_record/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/activerecord/lib/active_record/log_subscriber.rb
#
module RailsSemanticLogger
  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      IGNORE_PAYLOAD_NAMES = %w[SCHEMA EXPLAIN].freeze

      def sql(event)
        return unless logger.debug?

        payload = event.payload
        name    = payload[:name]
        return if IGNORE_PAYLOAD_NAMES.include?(name)

        log_payload         = {sql: payload[:sql]}
        log_payload[:binds] = bind_values(payload) unless (payload[:binds] || []).empty?
        log_payload[:allocations] = event.allocations
        log_payload[:cached] = event.payload[:cached]
        log_payload[:async] = true if event.payload[:async]

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

      # When multiple values are received for a single bound field, it is converted into an array
      def add_bind_value(binds, key, value)
        key = key.downcase.to_sym unless key.nil?

        if rails_filter_params_include?(key)
          value = "[FILTERED]"
        elsif binds.key?(key)
          value = (Array(binds[key]) << value)
        end

        binds[key] = value
      end

      def rails_filter_params_include?(key)
        filter_parameters = Rails.configuration.filter_parameters

        return filter_parameters.first.match? key if filter_parameters.first.is_a? Regexp

        filter_parameters.include? key
      end

      def logger
        ::ActiveRecord::Base.logger
      end

      def bind_values(payload)
        binds         = {}
        casted_params = type_casted_binds(payload[:type_casted_binds])
        payload[:binds].each_with_index do |attr, i|
          attr_name, value = render_bind(attr, casted_params[i])
          add_bind_value(binds, attr_name, value)
        end
        binds
      end

      def render_bind(attr, value)
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

      def type_casted_binds(casted_binds)
        casted_binds.respond_to?(:call) ? casted_binds.call : casted_binds
      end
    end
  end
end
