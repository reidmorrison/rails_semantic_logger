require 'semantic_logger'
require 'rails_semantic_logger/extensions/rails/server' if defined?(Rails::Server)
require 'rails_semantic_logger/engine'

module RailsSemanticLogger
  module Rack
    autoload :Logger, 'rails_semantic_logger/rack/logger'
  end
end
