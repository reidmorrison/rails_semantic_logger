# Rails Semantic Logger demo

A Rails app that sends its logs and metrics to an OpenTelemetry Collector, ClickHouse and Grafana,
built from this checkout. It needs only Docker.

```sh
docker compose -f demo/compose.yml up --build -d
open http://localhost:3001     # Grafana: the Rails, Jobs and Logs dashboards
open http://localhost:3000     # the app
```

The `traffic` service sends a steady mix of requests. For a burst, or a burst of errors:

```sh
docker compose -f demo/compose.yml run --rm traffic bin/rails demo:spike
docker compose -f demo/compose.yml run --rm traffic bin/rails demo:errors
```

ClickHouse answers SQL at http://localhost:8123/play (user `dev`, password `dev`). Stop the demo,
and delete its data, with `docker compose -f demo/compose.yml down --volumes`.

## How it is built

Nothing here is a maintained Rails app. `Dockerfile` runs `rails new` with `template.rb`, which adds
Rails Semantic Logger from this checkout, runs `rails generate rails_semantic_logger:observability`
as a user would, and adds the demo's endpoints, job and traffic tasks. `compose.yml` includes the
generator's own `compose.observability.yml`, so the demo runs exactly the stack, Collector config
and dashboards that the generator writes.

| Endpoint | Shape |
| --- | --- |
| `GET /orders` | Fast, cached list, with a nested payload |
| `GET /orders/:id` | A lookup; a 404 for a missing order |
| `GET /reports/:id` | Slow: a `measure_info` block with the `demo.report.duration` metric, then a `ReportJob` that is sometimes retried and sometimes fails |
| `GET /checkout` | One in ten raise, giving a 500 |

Every log entry carries the `request_id` and `user_id` named tags, so the Logs dashboard can follow
one request.

## End-to-end test

CI's "Demo end to end" job starts the demo, sends traffic, then runs
`check_dashboards.rb`, which runs the query of every dashboard panel through Grafana and fails when
any returns an error or no rows. To run it locally against a running demo:

```sh
ruby demo/check_dashboards.rb lib/generators/rails_semantic_logger/observability/templates/observability/grafana/dashboards demo
```
