# Sends sample requests, log entries and metrics to the local observability stack, so that a new
# install shows data in Grafana at once. Added by `bin/rails generate rails_semantic_logger:observability`.
#
#   bin/rails semantic_logger:traffic
#   bin/rails semantic_logger:traffic COUNT=200
namespace :semantic_logger do
  desc "Send sample requests, log entries and metrics to the observability stack"
  task traffic: :environment do
    logger  = SemanticLogger["SemanticLogger::Traffic"]
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!("localhost")

    Integer(ENV.fetch("COUNT", "50")).times do |iteration|
      session.get("/")
      session.get("/semantic_logger/not_found") if (iteration % 10).zero?
      logger.measure_info(
        "Sample work",
        metric:  "semantic_logger.sample.duration",
        payload: {iteration: iteration, order: {id: iteration, items: rand(1..5)}}
      ) { sleep(rand * 0.05) }
    end

    begin
      raise ArgumentError, "Sample exception from semantic_logger:traffic"
    rescue ArgumentError => e
      logger.error("Sample error", e)
    end

    # Send the log entries and metrics now, rather than waiting for the metric interval.
    SemanticLogger.flush
    puts "Sent sample data to the observability stack. Open Grafana: http://localhost:3001"
  end
end
