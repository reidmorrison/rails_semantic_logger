lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'rubygems'
require 'rake/clean'
require 'rake/testtask'
require 'date'
require 'rails_semantic_logger/version'

desc "Build gem"
task :gem  do |t|
  gemspec = Gem::Specification.new do |spec|
    spec.name        = 'rails_semantic_logger'
    spec.version     = RailsSemanticLogger::VERSION
    spec.platform    = Gem::Platform::RUBY
    spec.authors     = ['Reid Morrison']
    spec.email       = ['reidmo@gmail.com']
    spec.homepage    = 'https://github.com/ClarityServices/rails_semantic_logger'
    spec.date        = Date.today.to_s
    spec.summary     = "Improved logging for Ruby on Rails"
    spec.description = "Replaces the default Rails logger with SemanticLogger"
    spec.files       = FileList["./**/*"].exclude(/.gem$/, /.log$/,/^nbproject/).map{|f| f.sub(/^\.\//, '')}
    spec.has_rdoc    = true
    spec.add_dependency 'semantic_logger', '>= 2'
    spec.add_dependency 'rails', '>= 2'
  end
  Gem::Builder.new(gemspec).build
end

