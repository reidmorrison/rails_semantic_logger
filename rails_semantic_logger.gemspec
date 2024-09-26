$LOAD_PATH.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "rails_semantic_logger/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name                  = "rails_semantic_logger"
  s.version               = RailsSemanticLogger::VERSION
  s.platform              = Gem::Platform::RUBY
  s.authors               = ["Reid Morrison"]
  s.homepage              = "https://logger.rocketjob.io"
  s.summary               = "Feature rich logging framework that replaces the Rails logger."
  s.files                 = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  s.license               = "Apache-2.0"
  s.required_ruby_version = ">= 2.5"
  s.add_dependency "rack"
  s.add_dependency "railties", ">= 6.0"
  s.add_dependency "semantic_logger", "~> 4.16"
  s.metadata = {
    "bug_tracker_uri"       => "https://github.com/reidmorrison/rails_semantic_logger/issues",
    "documentation_uri"     => "https://logger.rocketjob.io",
    "source_code_uri"       => "https://github.com/reidmorrison/rails_semantic_logger/tree/v#{RailsSemanticLogger::VERSION}",
    "rubygems_mfa_required" => "true"
  }
end
