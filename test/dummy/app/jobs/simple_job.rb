class SimpleJob
  include Sidekiq::Worker

  def perform
    "SimpleJob is working"
  end
end
