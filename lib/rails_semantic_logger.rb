require "semantic_logger"
require "rails_semantic_logger/extensions/rails/server" if defined?(Rails::Server)
require "rails_semantic_logger/engine"

module RailsSemanticLogger
  module ActionController
    autoload :LogSubscriber, "rails_semantic_logger/action_controller/log_subscriber"
  end

  module ActionMailer
    autoload :LogSubscriber, "rails_semantic_logger/action_mailer/log_subscriber"
  end

  module ActionView
    autoload :LogSubscriber, "rails_semantic_logger/action_view/log_subscriber"
  end

  module ActiveJob
    autoload :LogSubscriber, "rails_semantic_logger/active_job/log_subscriber"
  end

  module ActiveRecord
    autoload :LogSubscriber, "rails_semantic_logger/active_record/log_subscriber"
  end

  module Rack
    autoload :Logger, "rails_semantic_logger/rack/logger"
  end

  module DelayedJob
    autoload :Plugin, "rails_semantic_logger/delayed_job/plugin"
  end

  module Sidekiq
    autoload :Defaults, "rails_semantic_logger/sidekiq/defaults"
    autoload :JobLogger, "rails_semantic_logger/sidekiq/job_logger"
    autoload :Loggable, "rails_semantic_logger/sidekiq/loggable"
  end

  autoload :Options, "rails_semantic_logger/options"

  # Swap an existing subscriber with a new one
  def self.swap_subscriber(old_class, new_class, notifier)
    subscribers = ActiveSupport::LogSubscriber.subscribers.select { |s| s.is_a?(old_class) }
    subscribers.each { |subscriber| unattach(subscriber) }

    new_class.attach_to(notifier)
  end

  def self.unattach(subscriber)
    subscriber_patterns(subscriber).each do |pattern|
      ActiveSupport::Notifications.notifier.listeners_for(pattern).each do |sub|
        next unless sub.instance_variable_get(:@delegate) == subscriber

        ActiveSupport::Notifications.unsubscribe(sub)
      end
    end

    ActiveSupport::LogSubscriber.subscribers.delete(subscriber)
  end

  def self.subscriber_patterns(subscriber)
    if subscriber.patterns.respond_to?(:keys)
      subscriber.patterns.keys
    else
      subscriber.patterns
    end
  end

  private_class_method :subscriber_patterns, :unattach
end

require("rails_semantic_logger/extensions/mongoid/config") if defined?(Mongoid)
require("rails_semantic_logger/extensions/active_support/logger") if defined?(ActiveSupport::Logger)
require("rails_semantic_logger/extensions/active_support/log_subscriber") if defined?(ActiveSupport::LogSubscriber)

begin
  require "rackup"
rescue LoadError
  # No need to do anything, will fall back to Rack
end
if defined?(Rackup::Server)
  require("rails_semantic_logger/extensions/rackup/server")
elsif defined?(Rack::Server)
  require("rails_semantic_logger/extensions/rack/server")
end
