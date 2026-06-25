# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Rails Semantic Logger is a Rails engine gem that **monkey-patches Rails to replace its loggers and log subscribers with [Semantic Logger](https://logger.rocketjob.io/)**, so that Rails produces structured logs directly instead of human-readable text that downstream systems have to parse. Rather than parsing Rails' text output (Started, Processing, Completed, Rendered, SQL, etc.), it replaces the built-in `ActiveSupport::LogSubscriber`s (and other loggers) wherever possible, emitting a message plus a structured payload that can be rendered as text, color, or JSON for centralized logging.

This gem only adapts Rails to Semantic Logger; the actual logging engine, appenders, and formatters live in the separate `semantic_logger` gem (a runtime dependency).

### The core maintenance challenge: tracking Rails' log subscribers

Rails' own log subscribers change between Rails versions, sometimes even in minor/patch releases. Because this gem reimplements those subscribers to emit structured payloads, that coupling makes it **inherently brittle**. The central, recurring maintenance task is:

1. Look at the log subscriber source for each supported Rails version (ActionController, ActionView, ActiveRecord, ActiveJob, ActionMailer, etc.).
2. Bring any upstream changes across into this gem's corresponding subscriber under `lib/rails_semantic_logger/<component>/log_subscriber.rb`.
3. Replace the upstream **text** output with **hash / structured** logging (message + payload) while preserving the new behavior.

When touching a subscriber, diff it against the matching Rails version's subscriber to confirm parity. To make this easier, some subscriber files carry a comment block at the top listing the upstream Rails source URLs for each supported version (one per `*-stable` branch), so a maintainer can jump straight to the canonical source to compare. See `lib/rails_semantic_logger/active_record/log_subscriber.rb` for the pattern; add or update the same links in the other subscribers as their upstream sources are reviewed.

As of Rails 8.1 there is a **second** source to cross-reference: each component now also ships a `*/structured_event_subscriber.rb` (e.g. `active_record/structured_event_subscriber.rb`), subclassing `ActiveSupport::StructuredEventSubscriber`. These are Rails' own structured-event emitters (message + hash, via `Rails.event` / the `ActiveSupport::EventReporter`), so they are the authoritative, Rails-maintained source for **field names and payload shape** when adding structured fields here. They are a *reference only*, not something this gem currently uses: Rails feeds two parallel pipelines from the same `ActiveSupport::Notifications` events, the classic `LogSubscriber` (text -> `Rails.logger`, which this gem swaps) and the new `StructuredEventSubscriber` (structured -> `Rails.event`). `Rails.event` ships with **no subscribers** by default, so the structured subscribers are dormant and do not conflict with our swapped subscribers. Note also that some structured events are emitted via `emit_debug_event` (only when `Rails.event.debug_mode?`, default development-only), so they are not a production-complete substitute. When syncing a subscriber, diff against **both** the classic `log_subscriber.rb` (for parity/behavior across 7.2/8.0/8.1) and, on 8.1, the `structured_event_subscriber.rb` (for the canonical field names).

This gem does **not** switch to `StructuredEventSubscriber`: it only exists in 8.1 (we still support 7.2/8.0), covers only a subset of components (and none of the non-Rails integrations such as Sidekiq/Mongoid/SolidQueue), and several events are debug-mode-only. Routing `Rails.event` into Semantic Logger would be an additive, opt-in bridge for a future major, not a replacement for swapping the `LogSubscriber`s.

### Relationship to semantic_logger

- The companion `semantic_logger` gem is usually checked out locally at **`../semantic_logger`** — reference it when you need to understand appender/formatter behavior.
- The two libraries are kept **in lock step at the major-version level**, so breaking changes in `semantic_logger` are paired with a matching `rails_semantic_logger` major version. Keep this in mind when bumping versions or relying on new `semantic_logger` features.

## Commands

Tests run via Appraisal across multiple Rails versions. Gems install into the global gem list.

```bash
appraisal install                  # install gems for every appraisal (regenerates gemfiles/)
rake                               # default task: run tests against ALL appraisals
rake test                         # run tests once against the current Gemfile
appraisal rails_8.0 rake          # tests for one Rails version
appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb            # single test file
appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb -n "/shows new article/"   # single test by name
rubocop                           # lint
```

Supported matrix (see `.github/workflows/ci.yml` and `Appraisals`): Rails 7.2 / 8.0 / 8.1 on Ruby 3.2–4.0. Minimum Ruby is 3.2; minimum Rails is 7.2. Set `BACKTRACE` env var to get full backtraces in test output.

## Architecture

### Engine bootstrap (`lib/rails_semantic_logger/engine.rb`)
This is the heart of the gem and the most important file to understand. The `Engine`:
- Exposes two config namespaces on the Rails app: `config.semantic_logger` (the `SemanticLogger` module itself) and `config.rails_semantic_logger` (a `RailsSemanticLogger::Options` instance).
- **Deletes** Rails' built-in `:initialize_logger` initializer and replaces it with its own. The replacement sets `SemanticLogger.default_level` from `config.log_level`, swaps `Rails::Rack::Logger` middleware for `RailsSemanticLogger::Rack::Logger`, builds the file appender (`log/<env>.log`), and assigns `Rails.logger`. If the log file can't be opened, it degrades gracefully to STDERR at `:warn`.
- Uses `ActiveSupport.on_load(...)` hooks to mix `SemanticLogger::Loggable` into `active_record`, `action_controller`, `action_mailer`, `action_view`, and sets the ActionCable logger.
- In `config.before_initialize` / `config.after_initialize`, replaces loggers for optional integrations when their constants are defined: Mongoid/Moped/Mongo, Resque, Sidekiq, SolidQueue, Delayed Job, ActiveModelSerializers.

### Log subscribers (`lib/rails_semantic_logger/<component>/log_subscriber.rb`)
Each Rails component subscriber (action_controller, action_view, active_record, active_job, action_mailer, solid_queue) is a custom `ActiveSupport::LogSubscriber` that translates ActiveSupport::Notifications events into semantic log entries with payloads instead of formatted strings. The engine installs these via `RailsSemanticLogger.swap_subscriber(old_class, new_class, notifier)` in `lib/rails_semantic_logger.rb`, which detaches Rails' default subscribers (handling the Rails-version differences in the notifier listener API) before attaching ours.

These are the files most affected by the "track Rails' log subscribers" maintenance task described in the Overview — they are reimplementations of upstream Rails subscribers and must be kept in sync with each supported Rails version.

### Options (`lib/rails_semantic_logger/options.rb`)
`RailsSemanticLogger::Options` is the public configuration surface, set via `config.rails_semantic_logger.*` in `application.rb`. Key flags: `semantic`, `started`, `processing`, `rendered`, `quiet_assets`, `add_file_appender`, `format` (`:default`/`:color`/`:json`/class/Proc), `filter`, `ap_options`, `action_message_format`, `replace_sidekiq_logger`, `replace_solid_queue_logger`, `console_logger`. The long comment block at the top of that file is the authoritative docs for each option, keep it in sync when changing defaults or behavior.

**Deprecated in favor of the appenders DSL (below):** `format`, `ap_options`, `filter`, and `console_logger`. Their setters warn via `RailsSemanticLogger.deprecator` (horizon `"6.0"`, set in `lib/rails_semantic_logger.rb`) through `Options#deprecate_appender_option(option, via:)` (the `via:` arg customizes the suggested replacement call, e.g. `appenders.add_console(...)`). The readers remain so the engine can still honor them on the legacy path. When adding another deprecation, reuse `deprecate_appender_option`.

### Appenders configuration (`lib/rails_semantic_logger/appenders.rb`)
The current way to configure log destinations. Instead of the single default `log/<env>.log` file appender plus the `format`/`filter`/`ap_options` options, an app declares appenders directly:

```ruby
config.rails_semantic_logger.appenders do |appenders|
  appenders.add(file_name: "log/#{Rails.env}.log", formatter: :json)  # always created, at init
  appenders.add_server(io: $stdout, formatter: :color)                # only when serving requests
  appenders.add_console(io: $stderr, formatter: :color)               # only inside `rails console`
end
```

Key points for maintainers:
- **The method names the *context* (when), the args are the *destination* (where).** `add` = always; `add_server` = serving contexts (defaults `$stdout`); `add_console` = the Rails console REPL (defaults `$stderr`). Both `add_server`/`add_console` accept any `SemanticLogger.add_appender` args; the default stream is applied only when no destination (`io`/`file_name`/`appender`/`logger`/`metric`, see `Appenders::DESTINATIONS`) is given, so a context can hold several appenders (e.g. server-only stdout *and* file).
- `Options#appenders?` is true once anything is declared (incl. `add_server`/`add_console`). When true, the engine **skips the default file appender** and the deprecated options no longer apply.
- **Materialization:** `add` appenders are created at init by `RailsSemanticLogger.add_appenders`. `add_server` appenders by `RailsSemanticLogger.add_server_appenders` (public), auto-called from the `rails server` patch (`extensions/rails/server.rb`) and the Sidekiq server block in the engine. `add_console` appenders by `RailsSemanticLogger.add_console_appenders`, called from the engine's `console do` hook. Both are idempotent via `SemanticLogger.appenders.console_output?`, and both fall back to a default screen appender (stdout for server, stderr for console) for backward compatibility when the app declared no appenders of its own (the console fallback is additionally gated by the deprecated `console_logger` toggle).
- **No heuristic server detection.** App servers without a first-party hook (bare `puma`, `rackup`, Passenger, Unicorn) are deliberately *not* auto-detected — no `$PROGRAM_NAME` matching, no `Puma::Launcher` patch ("sometimes works" is unsupportable). Those users call `RailsSemanticLogger.add_server_appenders` from the server's own definitive boot hook, e.g. `on_booted { RailsSemanticLogger.add_server_appenders }` in `config/puma.rb`.
- Tests live in `test/appenders_test.rb`.

### Extensions (`lib/rails_semantic_logger/extensions/`)
Monkey-patches / overrides of third-party and Rails internals, each loaded conditionally on the relevant constant being defined (e.g. `extensions/mongoid/config.rb`, `extensions/sidekiq/sidekiq.rb`, `extensions/active_support/tagged_logging.rb`, `extensions/action_dispatch/debug_exceptions.rb`). These keep integrations isolated and only activated when the host app uses that library.

### Integration loaders (Sidekiq, Delayed Job, SolidQueue)
Background job integrations live under their own namespaces (`sidekiq/`, `delayed_job/`, `solid_queue/`) providing job loggers and `Loggable` mixins, wired up from the engine only when the corresponding gem is present.

## Tests

Tests run against a full dummy Rails app in `test/dummy/` (controllers, models, jobs, mailers, sqlite3 DB). `test/test_helper.rb` boots that app, loads Sidekiq in server mode, and includes `SemanticLogger::Test::Minitest` helpers. `test/payload_collector.rb` captures emitted log entries so tests can assert on the structured payload rather than text output, this is the standard pattern for verifying subscriber behavior.

## Conventions

- RuboCop enforced (`.rubocop.yml`); run `rubocop` before finishing changes.
- Version lives in `lib/rails_semantic_logger/version.rb`; release is `rake publish` (tags, pushes, and `gem push`). Keep the major version in lock step with `semantic_logger`.
- **Documentation lives in the `semantic_logger` repo, not here.** The user-facing docs for this gem are at `../semantic_logger/docs/rails.md`. Do not edit that file directly without asking the user first.
