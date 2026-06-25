require "active_support/log_subscriber"
require "action_mailer"

# This subscriber is a reimplementation of Rails' own ActionMailer::LogSubscriber that emits
# structured (message + payload) log entries instead of formatted text. When Rails changes its
# subscriber, those changes must be brought across here. Compare against the upstream source for
# each supported Rails version:
#
#   Rails 8.1: https://github.com/rails/rails/blob/8-1-stable/actionmailer/lib/action_mailer/log_subscriber.rb
#   Rails 8.0: https://github.com/rails/rails/blob/8-0-stable/actionmailer/lib/action_mailer/log_subscriber.rb
#   Rails 7.2: https://github.com/rails/rails/blob/7-2-stable/actionmailer/lib/action_mailer/log_subscriber.rb
#
module RailsSemanticLogger
  module ActionMailer
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def deliver(event)
        # Rails gates this event with `subscribe_log_level :deliver, :debug`, so the upstream
        # subscriber only runs when the logger is at debug level (or lower). Match that here.
        return unless logger.debug?

        ex = event.payload[:exception_object]
        message_id = event.payload[:message_id]
        duration = event.duration.round(1)
        if ex
          log_with_formatter event: event, log_duration: true, level: :error do |_fmt|
            {
              message:   "Error delivering mail #{message_id} (#{duration}ms)",
              exception: ex
            }
          end
        else
          message =
            if event.payload[:perform_deliveries]
              "Delivered mail #{message_id} (#{duration}ms)"
            else
              "Skipped delivery of mail #{message_id} as `perform_deliveries` is false"
            end

          log_with_formatter event: event, log_duration: true do |_fmt|
            {message: message}
          end
        end
      end

      # An email was generated.
      def process(event)
        # Rails gates this event with `subscribe_log_level :process, :debug` and emits the message
        # at debug level. Match both the gating and the level here.
        return unless logger.debug?

        mailer   = event.payload[:mailer]
        action   = event.payload[:action]
        duration = event.duration.round(1)
        log_with_formatter event: event, level: :debug do |_fmt|
          {message: "#{mailer}##{action}: processed outbound mail in #{duration}ms"}
        end
      end

      private

      class EventFormatter
        def initialize(event:, log_duration: false)
          @event = event
          @log_duration = log_duration
        end

        def payload
          p = event.payload
          {}.tap do |h|
            h[:event_name]         = event.name
            h[:mailer]             = mailer
            h[:action]             = action
            h[:message_id]         = p[:message_id]
            h[:perform_deliveries] = p[:perform_deliveries]
            h[:subject]            = p[:subject]
            h[:to]                 = p[:to]
            h[:from]               = p[:from]
            h[:bcc]                = p[:bcc]
            h[:cc]                 = p[:cc]
            h[:date]               = date
            # Rails dumps the full encoded message at debug level via `debug { event.payload[:mail] }`.
            # The `deliver` event is debug-gated, so include it here whenever it is present.
            h[:mail]               = p[:mail] if p[:mail]
            h[:duration]           = event.duration.round(2) if log_duration?
            h[:args]               = formatted_args
          end
        end

        def date
          event.payload[:date].to_time.utc if event.payload[:date].respond_to?(:to_time)
        end

        private

        attr_reader :event

        def mailer
          event.payload[:mailer]
        end

        def action
          event.payload[:action]
        end

        def formatted_args
          return unless event.payload[:args].present?

          JSON.pretty_generate(event.payload[:args].map { |arg| format(arg) })
        end

        def format(arg)
          case arg
          when Hash
            arg.transform_values { |value| format(value) }
          when Array
            arg.map { |value| format(value) }
          when GlobalID::Identification
            begin
              arg.to_global_id
            rescue StandardError
              arg
            end
          else
            arg
          end
        end

        def log_duration?
          @log_duration
        end
      end

      def log_with_formatter(level: :info, **kw_args)
        fmt = EventFormatter.new(**kw_args)
        msg = yield fmt
        logger.public_send(level, **msg, payload: fmt.payload)
      end

      def logger
        ::ActionMailer::Base.logger
      end
    end
  end
end
