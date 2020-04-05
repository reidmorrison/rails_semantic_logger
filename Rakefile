# Setup bundler to avoid having to run bundle exec all the time.
require "rubygems"
require "bundler/setup"

require "rake/testtask"
require_relative "lib/rails_semantic_logger/version"

task :gem do
  system "gem build rails_semantic_logger.gemspec"
end

task publish: :gem do
  system "git tag -a v#{RailsSemanticLogger::VERSION} -m 'Tagging #{RailsSemanticLogger::VERSION}'"
  system "git push --tags"
  system "gem push rails_semantic_logger-#{RailsSemanticLogger::VERSION}.gem"
  system "rm rails_semantic_logger-#{RailsSemanticLogger::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

# By default run tests against all appraisals
if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  require "appraisal"
  task default: :appraisal
else
  task default: :test
end
