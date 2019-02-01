require 'semantic_logger'
require 'rails_semantic_logger/extensions/rails/server' if defined?(Rails::Server)
require 'rails_semantic_logger/engine'

module RailsSemanticLogger
  module ActionController
    autoload :LogSubscriber, 'rails_semantic_logger/action_controller/log_subscriber'
  end
  module ActionView
    autoload :LogSubscriber, 'rails_semantic_logger/action_view/log_subscriber'
  end
  module ActiveRecord
    autoload :LogSubscriber, 'rails_semantic_logger/active_record/log_subscriber'
  end
  module Rack
    autoload :Logger, 'rails_semantic_logger/rack/logger'
  end
  module DelayedJob
    autoload :Plugin, 'rails_semantic_logger/delayed_job/plugin'
  end

  autoload :Options, 'rails_semantic_logger/options'

  # Swap an existing subscriber with a new one
  def self.swap_subscriber(old_class, new_class, notifier)
    subscribers = ActiveSupport::LogSubscriber.subscribers.select { |s| s.is_a?(old_class) }
    subscribers.each { |subscriber| unattach(subscriber) }

    new_class.attach_to(notifier)
  end

  def self.unattach(subscriber)
    subscriber.patterns.each do |event|
      ActiveSupport::Notifications.notifier.listeners_for(event).each do |sub|
        next unless sub.instance_variable_get(:@delegate) == subscriber
        ActiveSupport::Notifications.unsubscribe(sub)
      end
    end

    ActiveSupport::LogSubscriber.subscribers.delete(subscriber)
  end
  private_class_method :unattach
end
