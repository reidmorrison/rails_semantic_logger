require_relative 'test_helper'

class ActiveJobTest < Minitest::Test
  if defined?(ActiveJob)
    class MyJob < ActiveJob::Base
      queue_as :my_jobs

      def perform(record)
        "Received: #{record}"
      end
    end
  end

  describe 'ActiveJob' do
    before do
     skip 'Older rails does not support ActiveJob' unless defined?(ActiveJob)
    end

    describe '.perform_now' do
      it 'sets the ActiveJob logger' do
        assert_kind_of SemanticLogger::Logger, MyJob.logger
      end

      it 'runs the job' do
        MyJob.perform_now('hello')
      end
    end

  end
end
