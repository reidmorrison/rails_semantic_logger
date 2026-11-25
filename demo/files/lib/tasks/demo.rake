require "net/http"

# Sends requests to the demo app over HTTP, as users would, from outside the app's process. It does
# not load the app, so it adds no log entries or metrics of its own.
class DemoTraffic
  # The endpoints of a steady mix, each with its share of the requests.
  MIX = [
    [60, -> { "/orders?status=#{%w[open paid shipped].sample}" }],
    [15, -> { "/orders/#{rand(1..220)}" }],
    [15, -> { "/reports/#{rand(1..50)}" }],
    [10, -> { "/checkout" }]
  ].freeze

  def initialize(url: ENV.fetch("APP_URL", "http://localhost:3000"))
    @uri = URI(url)
  end

  # A steady mix of requests, for `seconds`, or until stopped when it is 0.
  def steady(seconds:)
    deadline = seconds.zero? ? nil : Time.now + seconds
    until deadline && Time.now > deadline
      get(pick)
      sleep(rand(0.05..0.3))
    end
  end

  # A burst of concurrent requests, so that the request rate and latency move together.
  def spike(threads: 20, requests: 25)
    Array.new(threads) { Thread.new { requests.times { get(pick) } } }.each(&:join)
  end

  # A burst of failing checkouts, for the errors panels and a log search that finds the cause.
  def errors(count: 40)
    count.times { get("/checkout?fail=1") }
  end

  private

  def pick
    roll = rand(100)
    MIX.each do |share, path|
      return path.call if roll < share

      roll -= share
    end
  end

  def get(path)
    Net::HTTP.start(@uri.host, @uri.port) do |http|
      http.get(path, "X-Demo-User" => "user-#{rand(1..25)}")
    end
  rescue SystemCallError, IOError, Net::ReadTimeout => e
    warn("#{path}: #{e.class}: #{e.message}")
  end
end

namespace :demo do
  desc "Send a steady mix of requests to the demo app (DURATION=0 runs until stopped)"
  task :traffic do
    DemoTraffic.new.steady(seconds: Integer(ENV.fetch("DURATION", "0")))
  end

  desc "Send a burst of concurrent requests to the demo app"
  task :spike do
    DemoTraffic.new.spike
  end

  desc "Send a burst of failing checkouts to the demo app"
  task :errors do
    DemoTraffic.new.errors
  end
end
