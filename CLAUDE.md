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
