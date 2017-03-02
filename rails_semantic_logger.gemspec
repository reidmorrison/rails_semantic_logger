$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'rails_semantic_logger/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name                  = 'rails_semantic_logger'
  spec.version               = RailsSemanticLogger::VERSION
  spec.platform              = Gem::Platform::RUBY
  spec.authors               = ['Reid Morrison']
  spec.email                 = ['reidmo@gmail.com']
  spec.homepage              = 'https://github.com/rocketjob/rails_semantic_logger'
  spec.summary               = 'Scalable, next generation enterprise logging for Rails'
  spec.description           = 'Replaces the default Rails logger with SemanticLogger'
  spec.files                 = Dir['lib/**/*', 'LICENSE.txt', 'Rakefile', 'README.md']
  spec.license               = 'Apache-2.0'
  spec.has_rdoc              = true
  spec.required_ruby_version = '>= 2.1'
  spec.add_dependency 'rails', '>= 4.0'
  spec.add_dependency 'semantic_logger', '~> 4.0'
end
