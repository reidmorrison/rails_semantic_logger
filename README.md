# Rails Semantic Logger
[![Gem Version](https://img.shields.io/gem/v/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![Build Status](https://github.com/reidmorrison/rails_semantic_logger/workflows/build/badge.svg)](https://github.com/reidmorrison/rails_semantic_logger/actions?query=workflow%3Abuild) [![Downloads](https://img.shields.io/gem/dt/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Rails Semantic Logger replaces the Rails default logger with [Semantic Logger](https://logger.rocketjob.io/), so that Rails, your application code, and many common gems all log through structured logging instead of plain text.

When any large Rails application is deployed to production one of the first steps is to move to centralized logging, so that logs can be viewed and searched from a central location. That quickly falls apart when consuming human readable text logs:

- Log entries often span multiple lines (for example, stack traces), so unrelated lines end up interleaved in the centralized system.
- Complex regular expressions are needed to parse the text into machine readable fields for queries and alerts.
- Searches, alerts, and dashboards built on text are brittle: a small change to the logged text breaks them.
- Every log entry has a different format, making consistent searches difficult.

Switching to structured logging, or logs in JSON format, makes centralized logging in testing and production far more powerful. Rails Semantic Logger also collapses the several lines Rails normally logs per request into a single structured "Completed" line, while keeping every field (controller, action, status, durations, and so on) searchable.

## Installation

Add to your `Gemfile`:

~~~ruby
gem "rails_semantic_logger"
gem "amazing_print" # optional, colorizes the structured payload in development
~~~

Then run `bundle install`. That is all that is required: Rails Semantic Logger automatically replaces the standard Rails logger and writes to the usual Rails log file.

Remove the following gems if present, they conflict with or duplicate what this gem already does: `lograge`, `rails_stdout_logging`, `rails_12factor`.

## Out of the box

With no configuration at all, Rails Semantic Logger:

- Writes to `log/<environment>.log`, the same file Rails uses, colorized when Rails colorized logging is enabled.
- Logs to **standard out** when you run `rails server`, so you see requests in your terminal.
- Logs to **standard error** when you run `rails console`, so log lines do not get mixed up with command return values.
- Replaces the multi-line Rails request log with a single structured "Completed" line.

## Configuring where logs go: the appenders block

An **appender** is a destination for log output: a file, standard out, a centralized log service, and so on. Declare the appenders you want in a single block. **The method name says _when_ the appender is created; the arguments say _where_ it writes and _how_ it is formatted.**

| Method | Created when… | Default destination |
|--------|---------------|---------------------|
| `add` | Always, during Rails initialization | (you must specify one) |
| `add_server` | Only when serving requests: `rails server`, a rack server, Sidekiq in server mode | `$stdout` |
| `add_console` | Only inside a `rails console` session | `$stderr` |

The arguments to all three are exactly the arguments to `SemanticLogger.add_appender`, so anything Semantic Logger can log to, any of these can declare.

> **Important:** As soon as you declare **any** appender in this block, Rails Semantic Logger stops adding **all** of its automatic appenders (the default `log/<env>.log` file, the standard-out logger under `rails server`, and the standard-error logger in `rails console`). The block becomes the single source of truth for every destination.

A typical development setup, a color log file plus color to the screen while serving:

~~~ruby
config.rails_semantic_logger.appenders do |appenders|
  appenders.add(file_name: "log/#{Rails.env}.log", formatter: :color)
  appenders.add_server(formatter: :color) # → $stdout, only when serving
end
~~~

When running on a container platform (Docker, Kubernetes, Heroku), log JSON to standard out and let the platform collect it. Adding these lines to `config/application.rb` and removing other log overrides switches to structured logging automatically when running inside Kubernetes:

~~~ruby
config.semantic_logger.application = "my_application"
config.semantic_logger.environment = ENV["STACK_NAME"] || Rails.env
config.log_level = ENV["LOG_LEVEL"] || :info

if ENV["LOG_TO_CONSOLE"] || ENV["KUBERNETES_SERVICE_HOST"]
  config.rails_semantic_logger.appenders do |appenders|
    appenders.add(io: $stdout, formatter: :json)
  end
end
~~~

Because declaring an appender replaces the default file appender, JSON to stdout becomes the only destination, exactly what a container platform wants.

Once logs are emitted as structured JSON, a centralized logging system can parse them into a searchable hierarchy. Each field, including the nested `payload` and any `metric` data, becomes directly queryable, so you can build searches, alerts, and dashboards against well-defined fields instead of brittle text matching.

See [Configuring appenders](https://logger.rocketjob.io/rails#configuring-where-logs-go-the-appenders-block) for the full guide, including formatters, third-party destinations, tuning what Rails logs, and worked examples of querying the JSON.

## Documentation

For complete documentation see: https://logger.rocketjob.io/rails

## Upgrading

The way appenders (log destinations) are configured changed in v5. See the
[v4 to v5 migration guide](https://logger.rocketjob.io/rails#migrating-from-v4-to-v5) for the
before/after mapping, and [Migrating from earlier versions](https://logger.rocketjob.io/rails#migrating-from-earlier-versions)
for older releases.

## New Versions of Rails, etc.

The primary purpose of the Rails Semantic Logger gem is to patch other gems, primarily Rails, to make them support structured logging though Semantic Logger.

When new versions of Rails and other gems are published they often make changes to the internals, so the existing patches stop working.

Rails Semantic Logger survives only when someone in the community upgrades to a newer Rails or other supported libraries, runs into problems, 
and then contributes the fix back to the community by means of a pull request.

Additionally, when new popular gems come out, we rely only the community to supply the necessary patches in Rails Semantic Logger to make those gems support structured logging.

## Supported Platforms

For the complete list of supported Ruby and Rails versions, see the [Testing file](https://github.com/reidmorrison/rails_semantic_logger/blob/main/.github/workflows/ci.yml).

## Author

[Reid Morrison](https://github.com/reidmorrison)

[Contributors](https://github.com/reidmorrison/rails_semantic_logger/graphs/contributors)

## Versioning

This project uses [Semantic Versioning](http://semver.org/).
