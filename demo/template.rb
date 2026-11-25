# Rails application template that builds the Rails Semantic Logger demo app (demo/Dockerfile runs it):
#
#   rails new demo -m demo/template.rb
#
# It adds Rails Semantic Logger from this checkout, runs its observability generator just as a user
# would, then adds the demo's endpoints, job and traffic tasks. The demo then always matches what
# the generator writes, and doubles as its end-to-end test.

# Semantic Logger 6.0 is not released yet. Until it is, take it from its v6 branch.
gem "semantic_logger", github: "reidmorrison/semantic_logger", branch: "v6"
gem "rails_semantic_logger", path: File.expand_path("..", __dir__)

# Every log entry carries the request id, and the user that the traffic tasks claim to be, so that a
# log search can follow one request or one user.
environment <<~RUBY
  config.log_tags = {
    request_id: :request_id,
    user_id:    ->(request) { request.headers["X-Demo-User"] }
  }
RUBY

environment(<<~RUBY, env: "development")
  # The demo runs in Compose, where the traffic service calls the app by its service name.
  config.hosts << "app"

  # Cache in memory, so that the cache panels have reads, hits and misses to show.
  config.cache_store = :memory_store
RUBY

after_bundle do
  generate "rails_semantic_logger:observability"
  generate :model, "Order", "status:string", "total:decimal{10,2}", "items:integer", "--no-test-framework"

  route <<~RUBY
    resources :orders, only: %i[index show]
    resources :reports, only: :show
    get "checkout", to: "checkouts#show"
  RUBY

  file "app/controllers/orders_controller.rb", <<~RUBY
    # A fast list, cached for a few seconds, and a lookup that is a 404 for a missing order.
    class OrdersController < ApplicationController
      STATUSES = %w[open paid shipped].freeze

      def index
        status = STATUSES.include?(params[:status]) ? params[:status] : "open"
        orders = Rails.cache.fetch(["orders", status], expires_in: 5.seconds) do
          Order.where(status: status).order(:id).limit(20).to_a
        end
        logger.info("Listed orders", count: orders.size, filter: {status: status, limit: 20})
        render json: orders
      end

      def show
        render json: Order.find(params[:id])
      end
    end
  RUBY

  file "app/controllers/reports_controller.rb", <<~RUBY
    # A slow endpoint: builds a report inside a measure block, which logs its duration and records the
    # demo.report.duration metric, then stores it in the background.
    class ReportsController < ApplicationController
      def show
        report = logger.measure_info(
          "Built report",
          metric:  "demo.report.duration",
          payload: {report: {id: params[:id], kind: "sales"}}
        ) do
          sleep(rand(0.1..0.6))
          {id: params[:id], rows: rand(10..100)}
        end
        ReportJob.perform_later(params[:id].to_i)
        render json: report
      end
    end
  RUBY

  file "app/controllers/checkouts_controller.rb", <<~RUBY
    # An endpoint that fails: one checkout in ten, or every one with ?fail=1, raises, giving a 500.
    class CheckoutsController < ApplicationController
      class PaymentGatewayTimeout < StandardError; end

      def show
        if params[:fail] == "1" || rand < 0.1
          raise PaymentGatewayTimeout, "Payment gateway did not answer within 2 seconds"
        end

        logger.info("Checked out", order: {id: rand(1..200), items: rand(1..5)})
        render json: {status: "paid"}
      end
    end
  RUBY

  file "app/jobs/report_job.rb", <<~RUBY
    # Stores a report. One attempt in five fails and is retried, and every tenth report fails for good,
    # so the job dashboard shows retries and failures.
    class ReportJob < ApplicationJob
      class ReportStoreUnavailable < StandardError; end
      class EmptyReport < StandardError; end

      queue_as :reports
      retry_on ReportStoreUnavailable, wait: 1.second, attempts: 3

      def perform(report_id)
        logger.measure_info("Stored report", payload: {report_id: report_id}) do
          sleep(rand(0.05..0.3))
          raise EmptyReport, "Report \#{report_id} has no rows" if (report_id % 10).zero?
          raise ReportStoreUnavailable, "Report store unavailable" if rand < 0.2
        end
      end
    end
  RUBY

  append_to_file "db/seeds.rb", <<~RUBY
    if Order.none?
      200.times do |i|
        Order.create!(status: %w[open paid shipped].sample, total: rand(5.0..500.0).round(2), items: rand(1..5))
      end
    end
  RUBY

  file "lib/tasks/demo.rake", <<~RUBY
    require "net/http"

    # Sends requests to the demo app over HTTP, as users would, from outside the app's process. It does
    # not load the app, so it adds no log entries or metrics of its own.
    class DemoTraffic
      # The endpoints of a steady mix, each with its share of the requests.
      MIX = [
        [60, -> { "/orders?status=\#{%w[open paid shipped].sample}" }],
        [15, -> { "/orders/\#{rand(1..220)}" }],
        [15, -> { "/reports/\#{rand(1..50)}" }],
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
          http.get(path, "X-Demo-User" => "user-\#{rand(1..25)}")
        end
      rescue SystemCallError, IOError, Net::ReadTimeout => e
        warn("\#{path}: \#{e.class}: \#{e.message}")
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
  RUBY
end
