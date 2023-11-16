require "active_support/log_subscriber"
require "action_mailer"

module RailsSemanticLogger
  module ActionMailer
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def deliver(event)
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
        mailer   = event.payload[:mailer]
        action   = event.payload[:action]
        duration = event.duration.round(1)
        log_with_formatter event: event do |_fmt|
          {message: "#{mailer}##{action}: processed outbound mail in #{duration}ms"}
        end
      end

      private

      class EventFormatter
        def initialize(event:, log_duration: false)
          @event = event
          @log_duration = log_duration
        end

        def mailer
          event.payload[:mailer]
        end

        def payload
          {}.tap do |h|
            h[:event_name]         = event.name
            h[:mailer]             = mailer
            h[:action]             = action
            h[:message_id]         = event.payload[:message_id]
            h[:perform_deliveries] = event.payload[:perform_deliveries]
            h[:subject]            = event.payload[:subject]
            h[:to]                 = event.payload[:to]
            h[:from]               = event.payload[:from]
            h[:bcc]                = event.payload[:bcc]
            h[:cc]                 = event.payload[:cc]
            h[:date]               = date
            h[:duration]           = event.duration.round(2) if log_duration?
            h[:args]               = formatted_args
          end
        end

        def date
          if event.payload[:date].respond_to?(:to_time)
            event.payload[:date].to_time.utc
          elsif event.payload[:date].is_a?(String)
            Time.parse(date).utc
          end
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
          if defined?(mailer.constantize.log_arguments?) && !mailer.constantize.log_arguments?
            ""
          elsif event.payload[:args].present?
            JSON.pretty_generate(event.payload[:args].map { |arg| format(arg) })
          end
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
