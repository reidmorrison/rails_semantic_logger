require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'rails_semantic_logger/version'

task :gem do
  system 'gem build rails_semantic_logger.gemspec'
end

task :publish => :gem do
  system "git tag -a v#{RailsSemanticLogger::VERSION} -m 'Tagging #{RailsSemanticLogger::VERSION}'"
  system 'git push --tags'
  system "gem push rails_semantic_logger-#{RailsSemanticLogger::VERSION}.gem"
  system "rm rails_semantic_logger-#{RailsSemanticLogger::VERSION}.gem"
end

desc 'Run Test Suite'
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/**/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end

task default: :test
