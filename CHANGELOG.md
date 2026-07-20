# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [5.1.0] - 2026-07-20

- Require `semantic_logger` v5.1 or greater, keeping the two gems in lock step.
- Boot: a log file that cannot be opened is now caught during boot. Semantic Logger v5.1 opens the
  file appender's log file when it is created, so a bad path or insufficient permissions raises from
  `SemanticLogger.add_appender` and the engine's fallback (log to STDERR at `:warn`) runs as
  intended. Previously the failure surfaced asynchronously on the appender thread and the app booted
  against a silently broken appender. As a side effect the log file is now created as soon as the
  appender is added, even if nothing has been logged yet, matching the standard Rails logger.
- Boot: the rescue no longer reports a log file path problem when the failure came from the
  appenders block, where no path is involved. It now emits an accurate message per branch.
- ActionCable: fix an `ArgumentError` from `TaggedLoggerProxy` when the wrapped logger is a plain
  Ruby `Logger`, which accepts only a single progname argument. The v4.9 change always forwarded the
  full `(message, payload, exception)` signature, breaking `ActionCable::Connection::TestCase` tests
  such as `have_rejected_connection`. The extra arguments are now only forwarded to a logger method
  that can accept them. Fixes #317.
- Sidekiq: officially support Sidekiq 7 and 8, and test both in CI (Sidekiq 7.x on the Rails 7.2
  appraisal, Sidekiq 8.x on the Rails 8.0 and 8.1 appraisals).
- Sidekiq: remove support for Sidekiq 4, 5, and 6. These versions predate the gem's Rails 7.2 /
  Ruby 3.2 floor and were untested; the `Sidekiq::Logging` / server middleware patches, the pre-6.5
  `job_logger` wiring, the Sidekiq 5 `Worker` fallback, and the pre-7.1.6 error-handler branches
  are gone.
- Sidekiq: honor Sidekiq 8's `logged_job_attributes` setting, so additional job attributes can be
  added to the logging context (defaults to `bid` and `tags`, matching Sidekiq).
- Sidekiq: honor Sidekiq 8's `skip_default_job_logging` setting as an alternative to
  `RailsSemanticLogger::Sidekiq::JobLogger.perform_messages = false` for suppressing the
  `Start #perform` / `Completed #perform` messages.
- Add a `changelog_uri` to the gem metadata, so RubyGems links to this file. Thanks to
  [Philip Hallstrom](https://github.com/phallstrom).
- Remove the vestigial `sprockets < 4.0` development pin, which resolved to sprockets 1.0.2 with no
  `sprockets-rails` and therefore provided no Rails integration.

## [5.0.0] - 2026-06-29

- Bump the major version to keep it in lock step with Semantic Logger v5, and require
  `semantic_logger >= 5.0`.
- Appenders: add a `config.rails_semantic_logger.appenders do |appenders| ... end` block to declare
  log destinations by context. The method names the context (when) and the args name the
  destination (where): `add` is always created at init, `add_server` applies when serving requests
  (defaults to `$stdout`), and `add_console` applies inside the Rails console (defaults to
  `$stderr`). This replaces the single default `log/<env>.log` file appender plus the
  `format`/`filter`/`ap_options` options.
- Appenders: deprecate the `format`, `ap_options`, `filter`, `console_logger`, and
  `add_file_appender` options in favor of the appenders block. They still work but warn via the
  deprecator and will be removed in v6.
- Forking: rely on Semantic Logger v5's automatic reopen-after-fork (the `Process._fork` /
  `Process.daemon` hook reopens appenders in the child, once per process). Remove the now-redundant
  manual reopen hooks for Passenger, Resque, Spring, and SolidQueue, the rack/rackup `daemonize_app`
  overrides, and the DelayedJob plugin. Apps that opt out with `SemanticLogger.reopen_on_fork =
  false` are responsible for reopening themselves.
- ActionMailer: match Rails' `subscribe_log_level` gating so the `deliver` and `process` events are
  only emitted when the logger is at debug level, and log `process` at debug to match upstream.
- ActionMailer: include the full encoded message (`mail`) in the `deliver` payload, mirroring Rails'
  debug-level mail dump.
- ActionMailer: remove dead code from the log subscriber (the inapplicable `log_arguments?` branch
  and an unreachable, self-recursive date-string branch).
- ActionView: add `gc_time` to the `render_template`, `render_partial`, and `render_collection`
  payloads, matching the GC timing Rails now reports.
- ActionView: emit a `Rendered layout` completion event (with `duration`, `allocations`, and
  `gc_time`) to mirror Rails' `render_layout` subscriber. The upstream ActionView log subscriber is
  identical across Rails 7.2 / 8.0 / 8.1, so no version-specific behavior is required.
- ActionView: log under the name `ActionView::Base` (via `ActionView::Base.logger`) instead of
  `ActionView`, for consistency with the `ActiveRecord::Base`, `ActiveJob::Base`,
  `ActionMailer::Base`, and `ActionController::Base` logger names.
- ActiveJob: add the `enqueue_retry`, `retry_stopped`, and `discard` events (present in Rails since
  before 7.2 but never reimplemented here, so they previously produced no output).
- ActiveJob: add the Rails 8.1 Continuation events (`interrupt`, `resume`, `step_skipped`,
  `step_started`, `step`). The handlers are defined unconditionally; on Rails < 8.1 those
  notifications are never emitted, so no version-specific behavior is required.
- ActiveJob: fall back to `job.enqueue_error` when no `exception_object` is present, matching Rails,
  so a failed enqueue is no longer logged as a success.
- ActiveJob: add the `aborted` branch to `perform`, logging a halted `before_perform` callback as an
  error to match upstream.
- ActiveJob: add `enqueued_at` and `scheduled_at` to the event payload (when applicable), plus
  `executions`/`wait` on retry events and `step_name`/`step_cursor` on Continuation step events.
- ActiveRecord: handle the `strict_loading_violation` event (previously dropped entirely when our
  subscriber replaced Rails'), emitting the violation message plus a structured payload (`owner`,
  `association`, and `class` for non-polymorphic reflections).
- ActiveRecord: add `lock_wait` to the `sql` payload for async queries, matching Rails.
- ActiveRecord: only set `cached` in the `sql` payload when the result was served from the query
  cache, instead of writing `cached: nil` on every query.
- ActiveRecord: filter sensitive bind values via Rails' own `ActiveRecord::Base.inspection_filter`
  (derived from `config.filter_parameters`), replacing the previous partial filter that only
  handled a single leading Regexp. The upstream subscriber is identical across Rails 7.2 / 8.0 /
  8.1, so no version-specific behavior is required.
- Warn when a logger setting is configured too late to take effect. Settings consumed while the
  logger is built (the appenders block, `filter`, `format`, `ap_options`, `add_file_appender`,
  `semantic`, `replace_sidekiq_logger`, `replace_solid_queue_logger`) now print a warning when
  changed from `config/initializers/*`, which Rails loads *after* the logger is initialized.
  Settings consumed at the end of initialization (`started`, `processing`, `rendered`,
  `quiet_assets`, `action_message_format`) warn when changed after the application has booted.
  Configure logging in `config/application.rb` or `config/environments/<env>.rb`. Addresses #245.
- ActionController: restore the `processing` option, which had stopped taking effect. The
  `Processing` message was hardcoded to `:debug`; it is now logged at `:info` again when
  `config.rails_semantic_logger.processing` is true, matching the `started` and `rendered` options.
- Remove the long-deprecated and unused `named_tags` option. Supply a Hash to `config.log_tags`
  instead.
- Metrics (prototype): emit a Semantic Logger `metric` alongside each log entry that is logged at
  `:info`, `:warn`, or `:error`, so durations and event counts can be sent to a metrics backend.
  Names follow `rails.<component>.<event>`, dropping the `action_`/`active_` prefix (e.g.
  `rails.controller.process_action`, `rails.view.render.template`, `rails.job.perform`,
  `rails.mailer.deliver`, `rails.solid_queue.start_process`). Debug-level entries (e.g.
  ActiveRecord `sql`) carry no metric. **These metric names are a prototype and subject to change in
  a future release.**

## [4.20.0] - 2026-04-10

- Add a toggle to prevent replacement of the Sidekiq logger (`replace_sidekiq_logger`).
- Add configuration to toggle off Sidekiq "perform" messages.
- Sidekiq: log the replacement error handler's context at `:info` instead of `:warn`, matching
  upstream Sidekiq's default handler and removing duplicate noise (the exception itself is already
  logged at `:error` by the Job Logger). Fixes #271.
- Handle binary strings in `EventFormatter#format`. Fixes #284.
- Fix `Started` log line under Rails 7.1, with backward compatibility back to Rails 7.2. Fixes #281.
- Fix #282. Thanks @navidemad.

## [4.19.0] - 2025-12-09

- Add support for Rails 8.1.
- Move the bypass of double-counted query time methods to Rails 8.0.3 to catch the known
  double-counting issues reported in that version. Resolves #273.
- Handle `ActiveRecord::RuntimeRegistry.sql_runtime` private API move, and return early when
  setting runtime on Rails > 8.1.
- Avoid crashing in API-only (no assets) mode.

## [4.18.0] - 2025-07-25

- Respect `action_dispatch.log_rescued_responses`.
- Auto-detect SolidQueue and add `SolidQueue.on_start` support.
- Change how Rack requests are instrumented, and unsubscribe all listeners on Rails >= 7.1.
- Include `async: true` on async queries, with a workaround for a Rails 8 async query test issue.
- Fix the Rails version check in the ActiveRecord log subscriber.
- Allow customizing the message of an action log (`action_message_format`).
- Ensure filter params are still checked when cast to a regex, and are not revealed in SQL.
- Add missing conditionals to `ActionDispatch::DebugExceptions#log_error`.
- Replace Awesome Print with Amazing Print.
- Add CI against Rails 8.0.

## [4.17.0] - 2024-07-05

- Fix Sidekiq cross-version issues; add support for Sidekiq 7.2, 7.1.6, and 7.3.0.
- Initialize the Sidekiq 6 error handler, and only replace the default Sidekiq error handler when present.
- Use Sidekiq configuration where possible to override Sidekiq logging.

## [4.16.0] - 2024-07-01

- Fix the Sidekiq error handler not taking effect; duplicate the fixes to the Sidekiq v4 patches.
- Refine the metrics that are generated.

## [4.15.0] - 2024-06-27

- Add tests and support for Sidekiq 7, with a unified Sidekiq patch file.
- Avoid false positives during Resque detection.
- Ensure the load order of the optional Rackup dependency.
- Test the `ActionDispatch::DebugExceptions` extension and fix a couple of deprecations.

## [4.14.0] - 2023-11-16

- Add a test matrix entry for Rails 7.1.1 covering the `ActiveSupport::LogSubscriber#silenced?` patch,
  and only enable the `silenced?` patch for 7.1.1.
- Fix Ruby 3.2.2 and Rails 6.1 compatibility in the test suite.
- Fix Rack server deprecation in Rack 3.

## [4.13.0] - 2023-11-08

- Add support for Rails 7.1.
- Fix `log_arguments` of the mailer not working properly.
- Handle a nil logger in `ActiveJob::Logging`.
- Extend `#enqueue` and `#enqueue_at` in the ActiveJob subscriber to handle errors and aborts.
- Remove the `undef :broadcast` override since `ActiveSupport::Logger` dropped it.

## [4.12.0] - 2023-03-26

- Add support for Sidekiq 7.x.
- Add Ruby 3.2 to the CI matrix.
- Do not process the ActionController payload if params is not a Hash.
- Use `finish_with_state` inside `RailsSemanticLogger::Rack::Logger`.
- Require Rails subscribers only if defined.
- Avoid 2.7+ syntax that breaks compatibility with earlier Ruby versions.

## [4.11.0] - 2022-11-09

- Add ActionMailer logging with formatted args, and log exceptions correctly.
- Fix rendering of bind values for Rails 7.
- Support Sidekiq < 7.
- Only undefine `Rails::Server#log_to_stdout` if it is defined.

## [4.10.0] - 2022-02-05

- Test with Ruby 3.1.
- Avoid a warning when attempting to add a second console appender.

## [4.9.0] - 2021-12-28

- Add Rails 7 appraisals.
- Prepare for Semantic Logger v5, including direct access to appenders.
- Make it configurable whether to add the stderr logger when running a Rails console, and do not
  auto-add the console logger when one already exists.
- Use the legacy `thread_safe` gem for older versions of active_model_serializers.
- Eliminate method redefinition and `:: in void context` warnings.

## [4.6.2] - 2021-12-27

- Add Ruby 2.7 with Rails 6.1 to the CI test suite.

## [4.6.1] - 2021-08-15

- Set the minimum Ruby version to 2.5.
- Fix the bind column name for Rails 6.1.4.
- Silence method redefinition warnings.

## [4.6.0] - 2021-06-17

- Reopen Semantic Logger when running Rails as a Rack daemon. Fixes #69.
- Also log to stderr when running in a Rails console. Fixes #83.
- Log the payload when an ActiveJob `perform` raises an exception.
- Do not use `nil` as a payload key.

## [4.5.1] - 2021-05-03

- Add missing caching information to logs.
- Fix notification payload params absence.
- Use `request.remote_ip`. Fixes #128.
- Take Rails' `relative_url_root` into account when filtering Rack asset requests.

## [4.5.0] - 2021-01-24

- Test with Ruby 3.
- Add allocations to the payload for controller, view, and ActiveRecord logs.
- Add an option to disable logging for any ActiveJob jobs with sensitive arguments.
- Handle a nil bound key. Fixes #121.

## [4.4.6] - 2020-12-04

- Omit request and response from output.

## [4.4.5] - 2020-11-21

- Add support for Rails 6.1.
- Switch to Amazing Print.
- Use the correct namespace. Fixes #108.

## [4.4.4] - 2020-04-05

- Swap the ActiveJob log subscriber safely.

## [4.4.3] - 2019-10-10

- Use `Sidekiq.logger` when `Sidekiq::Logging` is unavailable.
- Fix unsubscribing notifications in Rails 6.
- Check for the specific method existence for the Spring `after_fork`.

## [4.4.2] - 2019-07-12

- Fix Rails 6 SQL logging with query cache.

## [4.4.1] - 2019-04-03

- Add proper informative ActiveJob events subscription, skipping subscription for older Rails versions.
- Remove minitest-rails to support the Rails 6 beta.

## [4.4.0] - 2019-02-06

- Remove the fork workaround now that Semantic Logger v4.4 handles it.

## [4.3.4] - 2019-02-01

- Use a class with default values. Fixes #84.

## [4.3.3] - 2018-12-18

- Fix the scope for `ActiveRecord::Base`.

## [4.3.2] - 2018-11-11

- Add support for Rails 5.2 and Rails 3.2.
- Add support for Delayed Job, with a plugin that reopens the log file `after_fork`.
- Log the source line from which the SQL query was submitted.
- Inspect the file param to prevent `to_json` from logging the entire file.
- Remove Rails monkey-patching where feasible, and replace `Rails::Rack::Logger`.
- Move Rails patches to `after_initialize`. Fixes #50.
- Fall back to `ActionController::Base.logger` when the logger returns nil. Fixes #62, #49.
- Keep calling an unused method so that Devise will work. Fixes #46.
- Only disable Sprockets asset quieting when logging is semantic.
- Fix bind variable logging, including attributes with several values.
- Remove the Concurrent Ruby logger replacement.

## [4.1.3] - 2017-06-16

- Fix non-colorized log output. Fixes #41.
- Allow the filter to be set via configuration. #19.

## [4.1.2] - 2017-05-24

- Switch to Rails version constants to support Rails 5.0.3.
- Fix the log subscriber monkey patch for Rails 5.0.3.
- Use `config.log_tags` for named tags.

## [4.1.1] - 2017-05-10

- Make backward compatible with Rails 4.2. Fixes #38.

## [4.1.0] - 2017-05-09

- Honor `ActionController::Base.enable_fragment_cache_logging`.
- Support named tags in the Rails Rack logger.
- Fix `log_subscriber` `Hash#except`.

## [4.0.1] - 2017-04-13

- Use Appraisal to manage gemsets.
- Fix ActiveRecord logging in Rails 5.1.

## [4.0.0] - 2017-03-02

- Update for Semantic Logger v4 (changed payload).
- Give Rack its own logger.
- Quiet assets by adding a filter to the `Rails.logger`. Fixes #48.
- Replace the Mongo logger.
- Replace ActionCable `#tag`, not `#tag_logger`. Fixes #29.

## [3.4.1] - 2016-12-01

- Replace the Mongo logger and update tests.

## [3.4.0] - 2016-10-13

- Include `SemanticLogger::Loggable` in `ActiveModelSerializers::SerializableResource`.

## [3.3.1] - 2016-06-01

- Add support for ActiveModelSerializers.
- Strip params from the path since they are already in the payload.
- Fix missing info in Rails 5. Fixes #16.

## [3.3.0] - 2016-04-12

- Switch to a Rails Engine, with an initial framework for tests.
- Support Controller `append_info_to_payload`; switch from a whitelist to a blacklist approach.
- Add a config option to disable the default Rails log file
  (`config.rails_semantic_logger.add_file_appender`).
- Add Travis CI testing for Rails 3.2, 4.1, 4.2, and 5.0.

## [3.1.1] - 2016-03-02

- Correctly handle `config.colorize_logging == false`.
- Handle the Rails 5 Beta 3 rename of the ActiveJob `#tag` method to `#tag_logger`.

## [3.1.0] - 2016-02-27

- Patch Rails so that it logs semantic data, and add configuration options.
- Patch the ActiveRecord log subscriber.
- Patch the ActionCable formatter.
- Enable one-line logging by default in production.
- Fix `Action::Controller.log_error`.

## [3.0.1] - 2016-02-14

- Fix ActionCable logger replacement, which stores its logger inside an instance of a
  configuration class. Fixes #10.

## [3.0.0] - 2016-02-08

- Update to Semantic Logger v3.

## [1.8.0] - 2015-12-09

- Replace Rails instance loggers to support inheritance.

## [1.7.0] - 2015-10-25

- Add stdout logging when running a Rails server configured to log to stdout. Fixes #7.
- Replace the Sidetiq logger if present.

## [1.6.1] - 2014-06-26

- Set `config.semantic_logger` to `SemanticLogger`.
- Move documentation to GitHub Pages.

## [1.6.0] - 2014-06-17

- Add support for the Spring gem.

## [1.5.0] - 2014-03-07

- Completely remove the Rails logger initializer so that the `:trace` level works. Fixes #5.
- Add a Sidekiq logger and detect older Resque versions. Confirmed working with Rails 3 and Rails 4.
- Fix an issue where Rails 4 was bypassing Semantic Logger in the controllers.

## [1.4.0] - 2014-01-30

- Replace the Resque logger if Resque is loaded, with support for process forking via `after_fork`
  callbacks. Fixes #2.
- Add Syslog appender examples.

## [1.2.0] - 2013-09-23

- Initial release: move Rails dependencies out of Semantic Logger and into this gem.
- Add tagged logging and colorized logging.
- Document Rails 4 support.
</content>
</invoke>
