require 'active_job'

module RailsSemanticLogger
  module ActiveJob
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def enqueue(event)
        log_with_formatter event: event do |fmt|
          "Enqueued #{fmt.job_info}"
        end
      end

      def enqueue_at(event)
        log_with_formatter event: event do |fmt|
          "Enqueued #{fmt.job_info} at #{fmt.scheduled_at}"
        end
      end

      def perform_start(event)
        log_with_formatter event: event do |fmt|
          "Performing #{fmt.job_info}"
        end
      end

      def perform(event)
        ex = event.payload[:exception_object]
        if ex
          logger.error ex
        else
          log_with_formatter event: event, log_duration: true do |fmt|
            "Performed #{fmt.job_info} in #{event.duration.round(2)}ms"
          end
        end
      end

      private

      class EventFormatter
        def initialize(event:, log_duration: false)
          @event = event
          @log_duration = log_duration
        end

        def job_info
          "#{job.class.name} (Job ID: #{job.job_id}) to #{queue_name}"
        end

        def payload
          {}.tap do |h|
            h[:event_name]      = event.name
            h[:adapter]         = adapter_name
            h[:queue]           = job.queue_name
            h[:job_class]       = job.class.name
            h[:job_id]          = job.job_id
            h[:provider_job_id] = job.try(:provider_job_id) # Not available in Rails 4.2
            h[:duration]        = event.duration.round(2) if log_duration?
            h[:arguments]       = formatted_args
          end
        end

        def queue_name
          adapter_name + "(#{job.queue_name})"
        end

        def scheduled_at
          Time.at(event.payload[:job].scheduled_at).utc
        end

        private

        attr_reader :event

        def job
          event.payload[:job]
        end

        def adapter_name
          event.payload[:adapter].class.name.demodulize.remove('Adapter')
        end

        def formatted_args
          JSON.pretty_generate(job.arguments.map { |arg| format(arg) })
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

      def log_with_formatter(**kw_args)
        fmt = EventFormatter.new(**kw_args)
        msg = yield fmt
        logger.info msg, fmt.payload
      end

      def logger
        ::ActiveJob::Base.logger
      end
    end
  end
end
