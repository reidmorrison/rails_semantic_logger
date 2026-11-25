# Runs the query of every panel of the generated Grafana dashboards through Grafana's query API, and
# fails when any of them returns an error or no rows. It proves that the dashboards, the data source,
# the Collector and ClickHouse fit together, against the data that the demo traffic produced.
#
# Usage:
#   ruby check_dashboards.rb <dashboards directory> <service name>
#
# Environment:
#   GRAFANA_URL: default http://localhost:3001
#   SINCE:       how far back to query, in minutes; default 30
#   SKIP:        comma-separated panel titles that may return no rows, such as "Retries and discards"
require "json"
require "net/http"
require "uri"

class DashboardCheck
  # The text that each dashboard variable takes while checking. A search or request id left empty
  # matches every entry.
  def initialize(dashboards_dir:, service:, grafana_url:, since_minutes:, skip:)
    @dashboards_dir = dashboards_dir
    @variables      = {"service" => service, "search" => "", "request_id" => ""}
    @grafana        = URI(grafana_url)
    @since_ms       = since_minutes * 60_000
    @skip           = skip
  end

  # Returns [Array<String>] a line for each panel that failed, empty when every panel returned rows.
  def failures
    panels.filter_map do |dashboard, panel|
      title = "#{dashboard} / #{panel['title']}"
      next if @skip.include?(panel["title"])

      rows = panel["targets"].sum { |target| rows_of(target) }
      next "#{title}: no rows" if rows.zero?

      puts "ok   #{title} (#{rows} rows)"
      nil
    rescue StandardError => e
      "#{title}: #{e.message}"
    end
  end

  private

  def panels
    Dir[File.join(@dashboards_dir, "*.json")].flat_map do |path|
      dashboard = JSON.parse(File.read(path))
      dashboard["panels"].reject { |panel| panel["type"] == "row" }.map { |panel| [dashboard["title"], panel] }
    end
  end

  def rows_of(target)
    now      = (Time.now.to_f * 1000).to_i
    query    = target.merge("rawSql" => interpolate(target["rawSql"]), "intervalMs" => 10_000, "maxDataPoints" => 500)
    body     = {"queries" => [query], "from" => (now - @since_ms).to_s, "to" => now.to_s}
    response = post("/api/ds/query", body)
    results  = JSON.parse(response.body).fetch("results")
    results.values.sum do |result|
      raise result["error"] if result["error"]

      result.fetch("frames", []).sum { |frame| frame.dig("data", "values")&.first&.size.to_i }
    end
  end

  # Grafana's front end fills in the dashboard variables; the query API does not, so it is done here,
  # as the `:sqlstring` format does: quoted, with each quote doubled.
  def interpolate(sql)
    sql.gsub(/\$\{(\w+)(?::sqlstring)?\}/) do
      value = @variables.fetch(Regexp.last_match(1))
      sql_string?(Regexp.last_match(0)) ? "'#{value.gsub("'", "''")}'" : value
    end
  end

  def sql_string?(reference) = reference.end_with?(":sqlstring}")

  def post(path, body)
    request = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
    request.body = JSON.generate(body)
    response = Net::HTTP.start(@grafana.host, @grafana.port) { |http| http.request(request) }
    raise "HTTP #{response.code}: #{response.body[0, 300]}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end

if $PROGRAM_NAME == __FILE__
  dashboards_dir, service = ARGV
  abort("Usage: ruby #{File.basename(__FILE__)} <dashboards directory> <service name>") unless dashboards_dir && service

  check = DashboardCheck.new(
    dashboards_dir: dashboards_dir,
    service:        service,
    grafana_url:    ENV.fetch("GRAFANA_URL", "http://localhost:3001"),
    since_minutes:  Integer(ENV.fetch("SINCE", "30")),
    skip:           ENV.fetch("SKIP", "").split(",").map(&:strip)
  )
  failures = check.failures
  failures.each { |failure| warn("FAIL #{failure}") }
  exit(failures.empty? ? 0 : 1)
end
