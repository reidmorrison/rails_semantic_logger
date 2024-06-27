class BadJob
  include Sidekiq::Worker

  sidekiq_options retry: false

  def perform
    raise ArgumentError, "This is a bad job"
  end
end
