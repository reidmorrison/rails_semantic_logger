lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'rubygems'
require 'rubygems/package'
require 'rake/clean'
require 'rake/testtask'
require 'rails_semantic_logger/version'

desc "Build gem"
task :gem  do |t|
  Gem::Package.build(Gem::Specification.load('rails_semantic_logger.gemspec'))
end

