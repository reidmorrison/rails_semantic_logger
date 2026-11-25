# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Rails Semantic Logger is a Rails engine gem that **monkey-patches Rails to replace its loggers and log subscribers with [Semantic Logger](https://logger.reidmorrison.com/)**, so that Rails produces structured logs directly instead of human-readable text that downstream systems have to parse. Rather than parsing Rails' text output (Started, Processing, Completed, Rendered, SQL, etc.), it replaces the built-in `ActiveSupport::LogSubscriber`s (and other loggers) wherever possible, emitting a message plus a structured payload that can be rendered as text, color, or JSON for centralized logging.

This gem only adapts Rails to Semantic Logger; the actual logging engine, appenders, and formatters live in the separate `semantic_logger` gem (a runtime dependency).

### The core maintenance challenge: tracking Rails' log subscribers

Rails' own log subscribers change between Rails versions, sometimes even in minor/patch releases. Because this gem reimplements those subscribers to emit structured payloads, that coupling makes it **inherently brittle**. The central, recurring maintenance task is:

1. Look at the log subscriber source for each supported Rails version (ActionController, ActionView, ActiveRecord, ActiveJob, ActionMailer, etc.).
2. Bring any upstream changes across into this gem's corresponding subscriber under `lib/rails_semantic_logger/<component>/log_subscriber.rb`.
3. Replace the upstream **text** output with **hash / structured** logging (message + payload) while preserving the new behavior.

When touching a subscriber, diff it against the matching Rails version's subscriber to confirm parity. To make this easier, every Rails component subscriber (action_controller, action_view, active_record, active_job, action_mailer) carries a comment block at the top listing the upstream Rails source URLs for each supported version (one per `*-stable` branch), so a maintainer can jump straight to the canonical source to compare. Keep those links current when the supported Rails versions change; `lib/rails_semantic_logger/active_record/log_subscriber.rb` shows the pattern. (`solid_queue/log_subscriber.rb` has no such block because SolidQueue is not a Rails component.)

The metrics subscribers under `lib/rails_semantic_logger/metrics/` follow the same upstream events (see Metrics below), so when Rails adds, renames or changes the payload of an event, check the component's metrics subscriber too.

As of Rails 8.1 there is a **second** source to cross-reference: each component now also ships a `*/structured_event_subscriber.rb` (e.g. `active_record/structured_event_subscriber.rb`), subclassing `ActiveSupport::StructuredEventSubscriber`. These are Rails' own structured-event emitters (message + hash, via `Rails.event` / the `ActiveSupport::EventReporter`), so they are the authoritative, Rails-maintained source for **field names and payload shape** when adding structured fields here. They are a *reference only*, not something this gem currently uses: Rails feeds two parallel pipelines from the same `ActiveSupport::Notifications` events, the classic `LogSubscriber` (text -> `Rails.logger`, which this gem swaps) and the new `StructuredEventSubscriber` (structured -> `Rails.event`). On 8.1, `Rails.event` ships with **no subscribers** by default, so the structured subscribers are dormant and do not conflict with our swapped subscribers. Note also that some structured events are emitted via `emit_debug_event` (only when `Rails.event.debug_mode?`, default development-only), so they are not a production-complete substitute. When syncing a subscriber, diff against **both** the classic `log_subscriber.rb` (for parity/behavior across 7.2/8.0/8.1) and, on 8.1, the `structured_event_subscriber.rb` (for the canonical field names).

Rails 8.2 (currently `main`, tested through the `rails_edge` appraisal) joins the two pipelines: each classic text `LogSubscriber` becomes an `ActiveSupport::EventReporter::LogSubscriber` that subscribes to `ActiveSupport.event_reporter` and is fed by the structured subscribers (Notifications -> `StructuredEventSubscriber` -> event reporter -> text `LogSubscriber`). Notifications still fire, so this gem's subscribers are unaffected, but `swap_subscriber` must also unsubscribe Rails' subscriber from the event reporter. 8.2 also moves some log output from direct `logger` calls into instrumented events that only Rails' text subscriber logs (CSRF failures became `csrf_*.action_controller`). Whenever Rails' text subscriber gains a handler, add a matching one here, or detaching Rails' subscriber silences that output.

This gem does **not** switch to `StructuredEventSubscriber`: it only exists in 8.1 (we still support 7.2/8.0), covers only a subset of components (and none of the non-Rails integrations such as Sidekiq/Mongoid/SolidQueue), and several events are debug-mode-only. Routing `Rails.event` into Semantic Logger would be an additive, opt-in bridge for a future major, not a replacement for swapping the `LogSubscriber`s.

### Relationship to semantic_logger

- The companion `semantic_logger` gem is usually checked out locally at **`../semantic_logger`** — reference it when you need to understand appender/formatter behavior.
- The two libraries are kept **in lock step at the major-version level**, so breaking changes in `semantic_logger` are paired with a matching `rails_semantic_logger` major version. Keep this in mind when bumping versions or relying on new `semantic_logger` features.
- Use only Semantic Logger's public API, such as `SemanticLogger.normalize_level`, `call_site?`, `backtrace?`, `application_backtrace` and `internal_logger`, never its internals (`Levels`, `Utils`, `Processor.logger`, the `*_level_index` accessors). When this gem needs something that only an internal gives, ask for a public method in `semantic_logger`.

## Commands

Tests run via Appraisal across multiple Rails versions. Gems install into the global gem list.

```bash
appraisal install                  # install gems for every appraisal (regenerates gemfiles/)
rake                               # default task: lint, then run tests against every released Rails appraisal (skips rails_edge)
rake test                         # run tests once against the current Gemfile
appraisal rails_8.0 rake          # tests for one Rails version
appraisal rails_edge rake test    # tests against Rails edge (rails/rails main)
appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb            # single test file
appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb -n "/shows new article/"   # single test by name
rubocop                           # lint
```

Supported matrix (see `.github/workflows/ci.yml` and `Appraisals`): Rails 7.2 / 8.0 / 8.1 on Ruby 3.2–4.0. Minimum Ruby is 3.2; minimum Rails is 7.2. CI also runs the `rails_edge` appraisal (rails/rails `main` on Ruby 4.0) with `continue-on-error`, so upstream breakage shows up early without failing the build. Set `BACKTRACE` env var to get full backtraces in test output.

## Architecture

### Engine bootstrap (`lib/rails_semantic_logger/engine.rb`)
This is the heart of the gem and the most important file to understand. The `Engine`:
- Exposes two config namespaces on the Rails app: `config.semantic_logger` (the `SemanticLogger` module itself) and `config.rails_semantic_logger` (a `RailsSemanticLogger::Options` instance).
- **Deletes** Rails' built-in `:initialize_logger` initializer and replaces it with its own. The replacement sets `SemanticLogger.default_level` from `config.log_level`, swaps `Rails::Rack::Logger` middleware for `RailsSemanticLogger::Rack::Logger`, and, when `config.rails_semantic_logger.metrics` is true, puts `RailsSemanticLogger::Rack::Metrics` first in the middleware stack and registers `RailsSemanticLogger::Metrics.attach` as an `after_initialize` hook. It creates the declared appenders, or the default file appender (`log/<env>.log`) when the app declared none, and assigns `Rails.logger`. If the log file can't be opened, it degrades gracefully to STDERR at `:warn`.
- Uses `ActiveSupport.on_load(...)` hooks to mix `SemanticLogger::Loggable` into `active_record`, `action_controller`, `action_mailer`, `action_view`, and sets the ActionCable logger.
- In `config.before_initialize` / `config.after_initialize`, replaces loggers for optional integrations when their constants are defined: Mongoid/Moped/Mongo, Resque, Sidekiq, SolidQueue, Sidetiq, Delayed Job, Bugsnag, IOStreams, ActiveModelSerializers.

### Log subscribers (`lib/rails_semantic_logger/<component>/log_subscriber.rb`)
Each Rails component subscriber (action_controller, action_view, active_record, active_job, action_mailer, solid_queue) is a custom `ActiveSupport::LogSubscriber` that translates ActiveSupport::Notifications events into semantic log entries with payloads instead of formatted strings. The engine installs these via `RailsSemanticLogger.swap_subscriber(old_class, new_class, notifier)` in `lib/rails_semantic_logger.rb`, which detaches Rails' default subscribers (handling the Rails-version differences in the notifier listener API, and on Rails 8.2 also unsubscribing them from `ActiveSupport.event_reporter`) before attaching ours.

These are the files most affected by the "track Rails' log subscribers" maintenance task described in the Overview — they are reimplementations of upstream Rails subscribers and must be kept in sync with each supported Rails version.

Each log subscriber except Action Controller's includes `RailsSemanticLogger::SilencedBelowLevel`, which answers Active Support's `silenced?` so that an event it would not log is not built for it, as Rails' own subscribers are silenced through `subscribe_log_level`. Each gives, in a private `log_level_of(name)`, the **highest** level at which it can log the event (`:error` for a job's `perform`, which logs a failure as an error), never the level of its usual entry, or an error would be dropped. A new handler in Active Job or Solid Queue needs its event in `LOG_LEVELS` (a test checks); an event without a level is never silenced. Action Controller logs through each controller's own logger, which `silenced?` cannot know, as it is given only the event's name, so it is not silenced.

Log entries carry **no** `metric:`: the metrics are recorded apart from the logs (below), so a log entry's level never decides a metric. Do not add `metric:` to a log call.

### Metrics (`lib/rails_semantic_logger/metrics/`, `rack/metrics.rb`)
Since v6 the Rails metrics are recorded by their own `ActiveSupport::Notifications` subscribers, whatever is logged, and only reach a backend once the app adds a Semantic Logger metric appender (until then they cost almost nothing). Each `RailsSemanticLogger::Metrics::<Component>` (ActionController, ActionView, ActiveRecord, ActiveJob, ActionMailer, Cache, SolidQueue) subclasses `Metrics::Subscriber` (an `ActiveSupport::Subscriber`), owns its event-to-metric mapping (names and dimensions), and records with `time`/`record_duration`/`increment` through `Subscriber.logger`, which each subclass defines as its component's logger (`::ActiveRecord::Base.logger`), read on each event: the one instance that the component's log entries use too (see "Replaced loggers"). Its level silences the log entries only: a metric is recorded at any level. Semantic Logger takes the name of the logger that records a metric as its meter. The engine gives Action Controller, Active Job, and the cache store a logger of their own name (`ActionController::Base`, `ActiveJob::Base`, `ActiveSupport::Cache::Store`), as Rails gives the first two `Rails.logger` and the cache none: through `RailsSemanticLogger.give_logger`, from initializers that run after Rails' `set_configs` and before the application's `config/initializers`, only while they still have `Rails.logger`. Solid Queue's metrics are attached only while `replace_solid_queue_logger` is on, as the Sidekiq job logger records only while `replace_sidekiq_logger` is. `Metrics::Subscriber.attach_to` refuses a subclass that defines no `logger`, without calling it, as that could load the component at boot. `Metrics::Subscriber#call` returns at once while its logger's `collecting_metrics?` is false (no metric appender), and swallows and reports once any exception, since Active Support raises a subscriber's exception into the instrumented code. Each recorder (the subscribers, `Rack::Metrics`, `Sidekiq::JobLogger`) lists the dimension keys it records as `DIMENSION_KEYS`; `Metrics.recorders` names them (the subscribers come from `Metrics::SUBSCRIBERS`, which `Metrics.attach` attaches), and the engine declares them all with `SemanticLogger.safe_dimension_keys |=` before it creates the appenders, so that the `config.filter_parameters` that this gem turns into sensitive keys never redact them. A new dimension key must be added to its recorder's `DIMENSION_KEYS`. Counters pass a UCUM unit (`{redirect}`) to `increment`. `Metrics.attach` attaches them all; the logger initializer registers it as an `after_initialize` hook when `config.rails_semantic_logger.metrics` is true, so the option is read once. A log subscriber must never unsubscribe every listener to an event by name (the Action View one detaches only the "Rendering" listeners), or it would detach the metrics too. `RailsSemanticLogger::Rack::Metrics`, first in the middleware stack, records `http.server.request.duration` through the `Rack` logger. The Sidekiq job logger records its own two metrics through `::Sidekiq.logger` (one meter for every job, the job's class a dimension), switched by `JobLogger.metrics`, which the engine sets from the same option.

**Naming:** OpenTelemetry semantic convention names and attributes where a convention exists (`http.server.request.duration`, `db.client.operation.duration`, `messaging.process.duration`, `messaging.client.sent.messages`, `messaging.client.operation.duration`, `error.type`, `code.function.name`), and otherwise names under the system that owns the event (`rails.action_controller.*`, `rails.action_view.*`, `rails.action_mailer.*`, `rails.cache.*`, `active_job.*`, `sidekiq.*`, `solid_queue.*`), with `.duration` histograms in seconds and plural counters. Every dimension must have a small, fixed set of values: never ids, paths, SQL text or free-form names. The full mapping and its reasoning are in `../semantic_logger/docs/rails.md` (Metrics) and the CHANGELOG.

Metrics come from Notifications, not `Rails.event`: on Rails 8.1+ the SQL, template and mailer structured events are debug-only, and `request_completed` has no HTTP method or route.

### Options (`lib/rails_semantic_logger/options.rb`)
`RailsSemanticLogger::Options` is the public configuration surface, set via `config.rails_semantic_logger.*` in `application.rb`. Key flags: `semantic`, `metrics`, `started`, `processing`, `rendered`, `quiet_assets`, `action_message_format`, `replace_sidekiq_logger`, `replace_solid_queue_logger`, `redact_filter_parameters`. The long comment block at the top of that file is the authoritative docs for each option, keep it in sync when changing defaults or behavior.

v6 removed the v5-deprecated appender options (`format`, `ap_options`, `filter`, `console_logger`, `add_file_appender`); the appenders DSL (below) replaces them. `RailsSemanticLogger.deprecator` stays registered as `Rails.application.deprecators[:rails_semantic_logger]` (horizon `"7.0"`) for future deprecations, so apps that silence it keep booting.

### Appenders configuration (`lib/rails_semantic_logger/appenders.rb`)
The current way to configure log destinations. Instead of the single default `log/<env>.log` file appender, an app declares appenders directly:

```ruby
config.rails_semantic_logger.appenders do |appenders|
  appenders.add(file_name: "log/#{Rails.env}.log", formatter: :json)  # always created, at init
  appenders.add_server(io: $stdout, formatter: :color)                # only when serving requests
  appenders.add_console(io: $stderr, formatter: :color)               # only inside `rails console`
end
```

Key points for maintainers:
- **The method names the *context* (when), the args are the *destination* (where).** `add` = always; `add_server` = serving contexts (defaults `$stdout`); `add_console` = the Rails console REPL (defaults `$stderr`). Both `add_server`/`add_console` accept any `SemanticLogger.add_appender` args; the default stream is applied only when no destination (`io`/`file_name`/`appender`/`logger`/`metric`, see `Appenders::DESTINATIONS`) is given, so a context can hold several appenders (e.g. server-only stdout *and* file).
- `Options#appenders?` is true once anything is declared (incl. `add_server`/`add_console`). When true, the engine **skips the default file appender** (`log/<env>.log`, in color unless `config.colorize_logging` is false). `add_server`/`add_console` give the default `:color` formatter only to a stream or a file (`Appenders::FORMATTED_DESTINATIONS`): a metric appender refuses a formatter in Semantic Logger v6.
- **Materialization:** `add` appenders are created at init by `RailsSemanticLogger.add_appenders`. `add_server` appenders by `RailsSemanticLogger.add_server_appenders` (public), auto-called from the `rails server` patch (`extensions/rails/server.rb`) and the Sidekiq server block in the engine. `add_console` appenders by `RailsSemanticLogger.add_console_appenders`, called from the engine's `console do` hook. Both are idempotent via `SemanticLogger.appenders.console_output?`, and both fall back to a default screen appender (stdout for server, stderr for console) when the app declared no appenders of its own.
- **No heuristic server detection.** App servers without a first-party hook (bare `puma`, `rackup`, Passenger, Unicorn) are deliberately *not* auto-detected — no `$PROGRAM_NAME` matching, no `Puma::Launcher` patch ("sometimes works" is unsupportable). Those users call `RailsSemanticLogger.add_server_appenders` from the server's own definitive boot hook, e.g. `on_booted { RailsSemanticLogger.add_server_appenders }` in `config/puma.rb`.
- Tests live in `test/appenders_test.rb`.

### Replaced loggers: one instance, no guards
The engine replaces the loggers of Rails' components and of the integrations (`ActiveRecord::Base.logger`, `SolidQueue.logger`, `Sidekiq.logger`, ...) with Semantic Logger loggers. Whatever in this gem logs or records metrics for a component uses that same instance (`::SolidQueue.logger`, `::Sidekiq.logger`), never a new one from `SemanticLogger[...]` with the same name: an application silences a logger by its level, which then applies to everything that logs through it.

Replacing one of these loggers with `nil`, a Ruby `Logger`, or any logger that is not a Semantic Logger one is not supported, and breaks both its log entries and its metrics. Do not add code that guards against it (falling back to another logger, or checking its class): document that applications must not replace them, and use the log level to silence one.

### Extensions (`lib/rails_semantic_logger/extensions/`)
Monkey-patches / overrides of third-party and Rails internals, each loaded conditionally on the relevant constant being defined (e.g. `extensions/mongoid/config.rb`, `extensions/active_support/tagged_logging.rb`, `extensions/action_dispatch/debug_exceptions.rb`). These keep integrations isolated and only activated when the host app uses that library. `extensions/action_view/structured_event_start.rb` is the exception: `lib/rails_semantic_logger.rb` requires it always, as it only registers an `on_load(:action_view)` hook, which checks for the Rails 8.1 class it patches (a `defined?` check at require time could miss an Action View that loads later).

Nothing that runs during boot, including the engine's `after_initialize` block, may load a Rails framework class such as `ActionView::Base`, `ActionController::Base` or `ActionDispatch::Response`, whether by referencing it or by reopening an autoloaded constant that requires it (as reopening `ActionController::Live` does). Rails 8.2 reports a framework loaded before the application has initialized, and the dummy app's test environment sets `config.action_on_early_load_hook = :raise`, so the suite fails to boot on Rails edge. Apply such patches from an `ActiveSupport.on_load` hook (see `extensions/action_controller/live.rb`), and look up framework loggers on first use rather than in a class body.

### Background job integrations (Sidekiq, SolidQueue, Delayed Job)
Sidekiq has the deepest integration: `sidekiq/` provides a job logger, a `Loggable` mixin, and error-handler defaults, wired up from the engine only when the gem is present. Sidekiq 7 and 8 are the supported range, both exercised in CI (Sidekiq 7.x on the `rails_7.2` appraisal, 8.x on `rails_8.0`/`rails_8.1`); pre-7 code paths were removed after v5.0.0. The job logger honors Sidekiq 8's `logged_job_attributes` (which job attributes go into the logging context) and `skip_default_job_logging` settings. `skip_default_job_logging` and `JobLogger.perform_messages` turn off only the `Start #perform` and `Completed #perform` log entries, never the job metrics (`sidekiq.queue.duration`, `messaging.process.duration`). Note that Sidekiq 7 passes its *logger* to the job logger's initializer while Sidekiq 8 passes its *config*, hence the `respond_to?(:[])` guard in `JobLogger#initialize`: the Sidekiq 8 options are only readable there when running Sidekiq 8. SolidQueue gets a swapped log subscriber (`solid_queue/log_subscriber.rb`). Delayed Job has no namespace of its own; the engine simply assigns `Delayed::Worker.logger`.

## Tests

Tests run against a full dummy Rails app in `test/dummy/` (controllers, models, jobs, mailers, sqlite3 DB). `test/test_helper.rb` boots that app, loads Sidekiq in server mode, and includes `SemanticLogger::Test::Minitest` helpers. `test/payload_collector.rb` captures emitted log entries so tests can assert on the structured payload rather than text output, this is the standard pattern for verifying subscriber behavior.

## Conventions

- RuboCop enforced (`.rubocop.yml`); run `rubocop` before finishing changes.
- Version lives in `lib/rails_semantic_logger/version.rb`; release is `rake publish` (tags, pushes, and `gem push`). Keep the major version in lock step with `semantic_logger`.
- **Documentation lives in the `semantic_logger` repo, not here.** The user-facing docs for this gem are at `../semantic_logger/docs/rails.md`. Do not edit that file directly without asking the user first.
