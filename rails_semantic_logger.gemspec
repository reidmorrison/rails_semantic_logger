$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require 'rails_semantic_logger/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = 'rails_semantic_logger'
  spec.version     = RailsSemanticLogger::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Reid Morrison']
  spec.email       = ['reidmo@gmail.com']
  spec.homepage    = 'https://github.com/reidmorrison/rails_semantic_logger'
  spec.summary     = "Improved logging for Ruby on Rails"
  spec.description = "Replaces the default Rails logger with SemanticLogger"
  spec.files       = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  spec.test_files  = Dir["test/**/*"]
  spec.license     = "Apache License V2.0"
  spec.has_rdoc    = true
  spec.add_dependency 'semantic_logger', '>= 2.5.0'
end
