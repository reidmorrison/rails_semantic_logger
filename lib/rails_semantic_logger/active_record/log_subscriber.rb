# This subscriber is a reimplementation of Rails' own ActiveRecord::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/activerecord/lib/active_record/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/activerecord/lib/active_record/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/activerecord/lib/active_record/log_subscriber.rb
#
# The upstream subscriber is functionally identical across Rails 7.2, 8.0, and 8.1 for everything
# that affects structured output. The only differences between those versions are in the internal
# `query_source_location` helper (used by `verbose_query_logs` to print the "↳ source" line) and a
# `:nodoc:` comment, neither of which changes the event payload. As a result no version-specific
# behavior is required here.
#
# As of Rails 8.1 there is also a parallel ActiveRecord::StructuredEventSubscriber (it emits
# structured events to Rails.event rather than text to Rails.logger). It is the authoritative,
# Rails-maintained reference for field names and payload shape; the fields below (e.g. :lock_wait
# and the strict_loading_violation payload) follow it. We do not use it (see CLAUDE.md), but diff
# against it when adding fields:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/activerecord/lib/active_record/structured_event_subscriber.rb
module RailsSemanticLogger
  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      IGNORE_PAYLOAD_NAMES = %w[SCHEMA EXPLAIN].freeze

      def strict_loading_violation(event)
        return unless logger.debug?

        payload    = event.payload
        owner      = payload[:owner]
        reflection = payload[:reflection]

        log_payload = {owner: owner.name, association: reflection.name}
        log_payload[:class] = reflection.klass.name unless reflection.polymorphic?

        logger.debug(
          message: reflection.strict_loading_violation_message(owner),
          payload: log_payload
        )
      end

      def sql(event)
        return unless logger.debug?

        payload = event.payload
        name    = payload[:name]
        return if IGNORE_PAYLOAD_NAMES.include?(name)

        log_payload               = {sql: payload[:sql]}
        log_payload[:binds]       = bind_values(payload) unless (payload[:binds] || []).empty?
        log_payload[:allocations] = event.allocations
        log_payload[:cached]      = true if payload[:cached]
        if payload[:async]
          log_payload[:async]     = true
          log_payload[:lock_wait] = payload[:lock_wait] if payload[:lock_wait]
        end

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
        key = key.downcase.to_sym

        value      = (Array(binds[key]) << value) if binds.key?(key)
        binds[key] = value
      end

      def logger
        ::ActiveRecord::Base.logger
      end

      def bind_values(payload)
        binds         = {}
        casted_params = type_casted_binds(payload[:type_casted_binds])
        payload[:binds].each_with_index do |attr, i|
          name  = bind_name(attr)
          value = render_bind(attr, filter(name, casted_params[i]))
          # Binds without a column name (casted binds: plain values, as passed to `select_all`) are
          # keyed by their parameter position, `$1`, `$2`, ..., as Rails 8.2 does.
          add_bind_value(binds, name || "$#{i + 1}", value)
        end
        binds
      end

      # The column name a bind is filtered and logged under, or nil when it has none.
      # Rails 7.2 to 8.1 also filter by the name of any bind that responds to `name`, including
      # `[column, value]` pairs, so those keep their name here and are filtered on every version.
      # A Symbol responds to `name` too, but as a bind it is a plain value, not a column.
      def bind_name(attr)
        if attr.is_a?(Array)
          column = attr.first
          column.name if column.respond_to?(:name)
        elsif attr.respond_to?(:name) && !attr.is_a?(Symbol)
          attr.name
        end
      end

      def render_bind(attr, value)
        return value unless attr.is_a?(ActiveModel::Attribute) && attr.type.binary? && attr.value

        "<#{attr.value_for_database.to_s.bytesize} bytes of binary data>"
      end

      # Filter sensitive bind values using the same parameter filter Rails uses for ActiveRecord,
      # which is derived from ActiveRecord::Base.filter_attributes (config.filter_parameters).
      def filter(name, value)
        return value if name.nil?

        filtered = ::ActiveRecord::Base.inspection_filter.filter_param(name.to_s, value)
        # filter_param returns the same object when nothing was filtered, otherwise a mask object
        # (a String delegate). Coerce the mask to a plain String for clean structured output.
        filtered.equal?(value) ? value : filtered.to_s
      end

      def type_casted_binds(casted_binds)
        casted_binds.respond_to?(:call) ? casted_binds.call : casted_binds
      end
    end
  end
end
