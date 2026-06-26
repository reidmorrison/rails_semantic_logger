require "action_cable/connection/tagged_logger_proxy"

# Upstream source (identical across supported versions):
#   https://github.com/rails/rails/blob/v7.2.2/actioncable/lib/action_cable/connection/tagged_logger_proxy.rb
#   https://github.com/rails/rails/blob/v8.0.2/actioncable/lib/action_cable/connection/tagged_logger_proxy.rb
#   https://github.com/rails/rails/blob/v8.1.3/actioncable/lib/action_cable/connection/tagged_logger_proxy.rb
module ActionCable
  module Connection
    class TaggedLoggerProxy
      # Mirrors upstream #tag, including the `respond_to?(:tagged)` guard so a
      # target logger without tagging support (e.g. when handed a non-tagged
      # ActiveRecord::Base.logger by the worker pool) simply yields. Diverges in
      # one place: upstream reads the already-applied tags via
      # `logger.formatter.current_tags` (ActiveSupport::TaggedLogging), but
      # Semantic Logger exposes them via `#tags`, so resolve from whichever the
      # target logger supports. See #220.
      def tag(logger, &)
        if logger.respond_to?(:tagged)
          current_tags = tags - applied_tags_for(logger)
          logger.tagged(*current_tags, &)
        else
          yield
        end
      end

      # Upstream defines the severity methods with a single-arg signature
      # (`message = nil`), which discards Semantic Logger's richer payload and
      # exception arguments and raises ArgumentError when they are supplied.
      # Redefine them to forward the full Semantic Logger signature down to the
      # wrapped logger, while still applying the connection's tags. See #220.
      %i[debug info warn error fatal unknown].each do |severity|
        define_method(severity) do |message = nil, payload = nil, exception = nil, &block|
          tag(@logger) { @logger.public_send(severity, message, payload, exception, &block) }
        end
      end

      private

      # Tags already applied to the target logger, so they are not duplicated.
      # Semantic Logger exposes them via `#tags`; ActiveSupport::TaggedLogging
      # via `formatter.current_tags`. Fall back to none when neither is present.
      def applied_tags_for(logger)
        if logger.respond_to?(:tags)
          Array(logger.tags)
        elsif logger.respond_to?(:formatter) && logger.formatter.respond_to?(:current_tags)
          logger.formatter.current_tags
        else
          []
        end
      end
    end
  end
end
