# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [6.0.0] - Unreleased

- Requires Semantic Logger v6. The two gems keep their major versions in step. See
  [Upgrading to Semantic Logger v6](https://logger.reidmorrison.com/upgrading.html#upgrading-to-semantic-logger-v6):
  it records a `metric:` at every log level once a metric appender is added, and its metric
  appenders send a snapshot each interval.
- Remove the appender options deprecated in v5: `config.rails_semantic_logger.format`,
  `ap_options`, `filter`, `console_logger` and `add_file_appender`. Setting one now raises
  `NoMethodError`. Declare the destinations instead, in `config.rails_semantic_logger.appenders`,
  with the formatter, filter and Amazing Print options on each appender. Without an appenders block
  the defaults are unchanged: `log/<environment>.log` in color (plain text when
  `config.colorize_logging` is false), and the screen under `rails server` and `rails console`.
- The default file appender no longer changes the formatter of the file and IO appenders that the
  application added before Rails initialized, through `config.semantic_logger.add_appender`. Each
  keeps the formatter it was given.
- An application that set `add_file_appender = false` or `console_logger = false` must declare all its
  appenders in `config.rails_semantic_logger.appenders`, including those it added with
  `config.semantic_logger.add_appender`: declaring any turns off the default file appender and the
  default screen appenders, which `console_logger` also controlled under `rails server` and Sidekiq.
  Deleting the line alone brings back `log/<environment>.log`, or the screen output.
- The deprecator, `Rails.application.deprecators[:rails_semantic_logger]`, stays registered, so
  configuration that silences it keeps working.
- Sidekiq: record its metrics under OpenTelemetry names, with dimensions, whether or not the
  `Start #perform` and `Completed #perform` entries are logged:
  - `sidekiq.queue.duration` (was `sidekiq.queue.latency`): how long the job waited in its queue, a
    histogram in seconds, with `messaging.system.name` (`sidekiq`) and `messaging.destination.name`
    (the queue). It was the `metric_amount` of the `Start #perform` entry, which Semantic Logger v6
    would record as a counter. A job with no `enqueued_at` records none.
  - `messaging.process.duration` (was `sidekiq.job.perform`): how long the job ran, a histogram in
    seconds, with the same dimensions plus `messaging.operation.name` (`process`),
    `messaging.sidekiq.job.class`, and `error.type`, the exception class, when the job raises.
  - `RailsSemanticLogger::Sidekiq::JobLogger.perform_messages = false` and Sidekiq 8's
    `skip_default_job_logging` turn off only the log entries now. The entries no longer carry a
    `metric`.
- `add_server` and `add_console` give the default `:color` formatter only to a stream (`io:`, the
  default) or a file (`file_name:`). Any other destination keeps its own default formatter: a metric
  appender, which Semantic Logger v6 refuses a formatter for with an `ArgumentError`, an appender
  instance, which ignores it, and a logger (`logger:`) or an appender named by a Symbol (such as
  `appender: :syslog`), which no longer write colored text.
- Record `http.server.request.duration`, OpenTelemetry's stable metric for HTTP server requests: a
  histogram in seconds of the whole request, until its body is closed, with `http.request.method`,
  `url.scheme`, `http.route` (the route template without `(.:format)`, and none when no route served
  the request), `http.response.status_code`,
  and `error.type` (the status code of a 5xx, or the class of an exception that escapes). A new
  middleware, `RailsSemanticLogger::Rack::Metrics`, first in the middleware stack, records it. A
  hijacked connection, such as a WebSocket, is not recorded. Turn off the Rails and Sidekiq metrics
  with `config.rails_semantic_logger.metrics = false`.
- Action Controller: record its metrics apart from its log entries, which no longer carry a
  `metric`, and rename them under `rails.action_controller`, since no OpenTelemetry convention covers
  them:
  - `rails.action_controller.process_action.duration` (was `rails.controller.process_action`), with
    `code.function.name` (`ArticlesController#index`), `http.response.status_code`, and `error.type`
    when the action raised. For the whole request, use `http.server.request.duration`.
  - Counters `rails.action_controller.halted_callbacks` (by `rails.action_controller.filter`),
    `rails.action_controller.rescued_exceptions` (by `error.type`), `rails.action_controller.redirects`
    (by `http.response.status_code` and `code.function.name`),
    `rails.action_controller.unsafe_redirects` (by `rails.action_controller.redirect.kind`, `open` or
    `path_relative`), and `rails.action_controller.csrf_events` (by
    `rails.action_controller.csrf.reason`).
  - Histograms `rails.action_controller.send_file.duration`, `send_data.duration`, and
    `fragment_cache.duration` (by `rails.cache.operation.name`).

## [5.3.0] - 2026-11-20

- Requires Semantic Logger 5.3 or later.
- Rails 8.2: detach Rails' own log subscribers from `ActiveSupport.event_reporter`. Rails 8.2 moves
  its framework log subscribers off `ActiveSupport::Notifications` and onto the event reporter, so
  they kept running next to the semantic subscribers and every request, query, render, mail and job
  was logged twice. Fixes #332, in #333. Thanks to [Raheel Khan](https://github.com/raheelkhan).
- Active Job: replace Rails' log subscriber even when Active Job has not loaded by
  `after_initialize`. With lazy loading (the default in development and test) the semantic
  subscriber was never attached, so jobs were logged only as Rails' text lines. Eager-loaded
  applications (the production default) were not affected. Fixed in #333.
- Rails 8.2: log CSRF failures. Rails 8.2 reports them as `csrf_request_blocked`,
  `csrf_javascript_blocked` and `csrf_token_fallback` events instead of calling `logger.warn`
  directly, and only its own text log subscriber logged those events, so detaching it silenced the
  warnings. They are now logged at `:warn`, as Rails does, with `controller`, `action` and
  `sec_fetch_site` in the payload, while `log_warning_on_csrf_failure` is on.
- Rails 8.2: stop loading `ActionView::Base` and `ActionDispatch::Response` while the application
  boots. Rails 8.2 logs a "was loaded before application initialization" warning for each when eager
  loading is off (development and test by default), and fails the boot when
  `config.action_on_early_load_hook = :raise`. The `ActionController::Live` patch, which loaded
  `ActionDispatch::Response`, is now applied once Action Controller loads, and the Action View
  subscriber looks up its logger on first use instead of when its file loads.
- Active Record: key SQL bind values that have no column name by their parameter position (`$1`,
  `$2`, ...), as Rails 8.2 now does in its own SQL logs. These are casted binds, plain values such
  as those passed to `connection.select_all(sql, name, binds)`. All of them were previously logged
  under a single `nil` key, so a query with several such binds logged `binds: {nil: ["foo", 2]}`
  instead of `binds: {"$1": "foo", "$2": 2}`. Applies to every supported Rails version.
  **Log output change:** the `nil` bind key is gone, so update any log query, dashboard or alert
  that matches `payload.binds.nil` to match the positional keys instead. Binds that name their
  column, including `[column, value]` pairs, are still keyed and filtered by that name.
- Rails 8.1+: log open redirects reported by `config.action_controller.action_on_open_redirect =
  :notify`, and path relative redirects reported by
  `config.action_controller.action_on_path_relative_redirect = :notify`. Rails' text log subscriber
  never logs the `open_redirect.action_controller` and `unsafe_redirect.action_controller` events
  (on Rails 8.2 only its structured event subscriber reports open redirects), so neither was
  logged. Both are now logged at `:warn` with the redirect's stack trace, cleaned of gem frames, as
  the backtrace: open redirects with `location`, `request_method` and `request_path` in the payload,
  under the logger of the controller handling the request, and path relative redirects with `url`.
  When cleaning would remove every frame, as for a redirect from an engine's controller, the
  backtrace keeps instead the frames from the first one in the file that defines the controller's
  action, or every frame when there is none, with gem paths shortened.
- Active Job: support `config.active_job.verbose_enqueue_logs`, which Rails turns on in
  development for new applications. When it is on, each enqueue entry has the application code
  that enqueued the job as `source` in its payload, such as
  `source: "app/controllers/orders_controller.rb:18:in 'OrdersController#create'"`, where Rails'
  own log adds a `↳` line. It was ignored on every Rails version. As Rails does, the source is the
  first frame of the call stack that the application's `Rails.backtrace_cleaner` keeps, and every
  info and error entry gets one when there is such a frame: a job performed inline, such as with
  `perform_now`, has the code that performed it, while the perform entries of a job performed by a
  worker have none, and its Continuation step entries (Rails 8.1+) have the job's line. A job
  enqueued after its transaction commits (`enqueue_after_transaction_commit`, Rails 8.1+) is
  logged at the commit, so its source is the code that opened the transaction, as in Rails' own
  log. To use another cleaner, assign
  `RailsSemanticLogger::ActiveJob::LogSubscriber.backtrace_cleaner`.
- Active Job: close the parentheses in the message of an `enqueue` or `enqueue_at` that failed
  with an error, which reads as Rails words it:
  `Failed enqueuing MyJob (Job ID: 1a2b) to Sidekiq(default): RuntimeError (boom)`.
  It ended `... to Sidekiq(default) (RuntimeError (boom)`, missing a closing
  parenthesis, since 4.13.0. **Log output change:** update any log query or alert that matches the
  old message.
- Active Record: support `config.active_record.verbose_query_logs`, which Rails turns on in
  development for new applications. When it is on, each query entry, and each strict loading
  violation, has the application code that caused it as `source` in its payload, such as
  `source: "app/models/user.rb:12:in 'User.recent'"`, where Rails' own log adds a `↳` line. It
  was ignored on every Rails version. As Rails does, the source is the first frame of the call
  stack that the application's `Rails.backtrace_cleaner` keeps. To use another cleaner, assign
  `RailsSemanticLogger::ActiveRecord::LogSubscriber.backtrace_cleaner`.
- Action Controller: clean the backtraces it logs with the application's `Rails.backtrace_cleaner`,
  as Rails 8.1 does for its own subscriber, on every supported Rails version. Application frames
  are logged relative to `Rails.root`, and the application's backtrace silencers apply. This covers
  the open and path relative redirect backtraces, and the `source` of a `Redirected to` entry when
  `ActionDispatch.verbose_redirect_logs` is on (Rails 8.1+). **Log output change:** that `source`
  was an absolute path, such as
  `/srv/app/app/controllers/articles_controller.rb:12:in 'ArticlesController#create'`, and is now
  `app/controllers/articles_controller.rb:12:in 'ArticlesController#create'`, as in Rails' own log.
  On Rails 7.2 to 8.1, Rails' cleaner also leaves out frames outside `app/`, `config/`, `lib/` and
  `test/`, as Rails' own log does, so code in other directories, such as `packs/` or a local engine
  in `engines/`, is no longer the `source`; add to `Rails.backtrace_cleaner` to change that. To use
  another cleaner, assign `RailsSemanticLogger::ActionController::LogSubscriber.backtrace_cleaner`.
- Action Controller: skip logging, as Rails does, when the controller has no logger and
  `ActionController::Base.logger` is nil, instead of raising `NoMethodError` from the subscriber.
- Action Controller: leave the request out of the `unpermitted_parameters` context, as Rails'
  structured event subscriber does. The request refers back to itself, so the `:json` formatter
  overflowed the stack and the `Unpermitted parameter` line was never written, and the appender
  thread walked the request's env while the request was still using it. Fixed in #338. Thanks to
  [Philippe Vaucher](https://github.com/Silex).
- CI also tests against Rails edge (rails/rails `main`). A failure there is reported but does not
  fail the build, and the default `rake` task still runs only the released Rails versions.
- Clean the backtraces of logged exceptions with `Rails.backtrace_cleaner` by default, as Rails' own
  log does. Sets Semantic Logger 5.3's `SemanticLogger.backtrace_cleaner`, so the text formatters
  (`:default`, `:color`, ...) and the `:json` formatter, including the appenders that send JSON
  (HTTP, TCP, UDP, Kafka, ...), write only the application's frames, relative to `Rails.root`. The
  silencers in `config/initializers/backtrace_silencers.rb` apply, and an exception with no
  application frames, such as one raised entirely within a gem, keeps its whole backtrace. This
  covers every exception logged through Semantic Logger: requests, Active Job and Sidekiq job
  failures, and the application's own `logger.error(exception)` calls. Error services, such as
  Sentry or Bugsnag, still receive the full backtrace. See
  [discussion #236](https://github.com/reidmorrison/rails_semantic_logger/discussions/236).
  **Log output change:** backtraces were logged in full, with absolute paths. To log full
  backtraces again, set the `BACKTRACE` environment variable as with the rest of Rails, opt out
  with `config.semantic_logger.backtrace_cleaner = nil` in `config/application.rb`, or opt out
  for one appender with `formatter: {json: {backtrace_cleaner: false}}`.
- Action Dispatch: log a routing error, and the other exceptions in
  `ActionDispatch::ExceptionWrapper.silent_exceptions` (`ActionController::RoutingError` and
  `ActionDispatch::Http::MimeNegotiation::InvalidType`), without its backtrace when none of its
  frames is the application's, as Rails' own log does. Every other exception is logged as before. A
  request for a missing route, such as `/apple-touch-icon.png`, is now one line, after the
  response's status, instead of dozens of middleware frames:
  `Rails -- 404 Not Found -- Exception: ActionController::RoutingError: No route matches [GET] "/apple-touch-icon.png"`.
  It is logged with Semantic Logger's `log_exception: :partial`, so the entry has the exception's
  class and message but not the exception: the `:json` formatter writes them in the `message`
  rather than as an `exception`, and Semantic Logger's own error service appenders, such as
  `sentry_ruby`, receive a message rather than an exception. The message also names each exception
  that caused it, which Rails lists as "Caused by", without their backtraces, such as the
  `Mime::Type::InvalidMimeType` behind an invalid `Accept` header. Rails renders the exception, and error
  services hooked into Rails report it, as before. With `BACKTRACE` set, or a routing error raised
  from application code, the exception is logged with its backtrace;
  `config.semantic_logger.backtrace_cleaner = nil` does not change this. To leave these out of the
  log altogether, set `config.action_dispatch.log_rescued_responses = false`.
  See [discussion #236](https://github.com/reidmorrison/rails_semantic_logger/discussions/236).
- Action Dispatch: log a `SyntaxError` raised while handling a request, such as one in a file that
  Rails loads on demand in development. It was logged as
  `ArgumentError: Invalid value for logger exception`, since Rails passes it wrapped in an
  `ActiveSupport::SyntaxErrorProxy`.
- Redact the application's `config.filter_parameters` from every log entry by default, not only
  from the request parameters that Rails filters itself. Sets Semantic Logger 5.3's
  `SemanticLogger.sensitive_keys` once the application has initialized, so the value of every key
  that the filters match is written as `"[FILTERED]"` in the payload, named tags, and context of
  every entry, at any depth, by every appender. Keys are matched as written and in snake_case, so
  an `X-Api-Key` header in a payload is redacted, as `x_api_key`. See
  [semantic_logger discussion #272](https://github.com/reidmorrison/semantic_logger/discussions/272).
  **Log output change:** the filters match any key that contains them, so Rails' default filters
  (`:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`)
  also redact keys such as `max_tokens`, `token_count`, `cache_key`, and `api_key_id`, every
  `email`, and the `concurrency_key` of Solid Queue's entries. To opt out, set
  `config.rails_semantic_logger.redact_filter_parameters = false`; assigning
  `SemanticLogger.sensitive_keys = nil` does not opt out, since it cannot be told apart from never
  assigning it. An application that assigns its own `SemanticLogger.sensitive_keys` keeps them.
  Limits:
  - Rails' default filters do not match `Authorization` or `Cookie`; add them, e.g.
    `config.filter_parameters += [:authorization, :cookie]`.
  - Active Job `arguments` and Action Mailer `args` are logged as JSON text, which is not redacted.
    For a job that takes a secret, leave its arguments out of the log with
    `self.log_arguments = false`.
  - Proc filters are not applied, since they change values rather than match keys.
  - A dotted filter, such as `"credit_card.code"`, only matches a key named that, not a `code` key
    nested in `credit_card`. That includes the `"model.attribute"` filters that Rails adds for
    Active Record encrypted attributes.
  - Entries logged before the application has initialized may not be redacted.
- Record where each entry was logged, with Semantic Logger 5.3's `SemanticLogger.call_site_level`:
  the file, line, and method of the code behind it. The text formatters write it after the thread,
  such as `[1234:puma 1 articles_controller.rb:15 ArticlesController#index]`, and the `:json`
  formatter as `file`, `line`, and `method`. Unlike `backtrace_level`, it reads only the frames up to
  that code, about a microsecond per entry. For the entries of Rails' events, Rails Semantic Logger
  reads the stack up to the first application frame, with the subscriber's backtrace cleaner, which
  costs more. When there is none, it reads up to where Rails took over from the application, or the
  whole stack, when Rails did not take over, or a `verbose_*_logs` option needs the entry's source.
  - On by default in development, at every level. **Log output change:** to turn it off, or choose
    another level, set `config.semantic_logger.call_site_level = nil` (or `:info`, ...) in
    `config/application.rb`, `config/environments/development.rb`, or an initializer.
  - In the Rails console it replaces `backtrace_level`, which captured a backtrace for every entry
    at the default level. Backtraces in the console are back to the `:error` default.
  - The entries for Rails' events record the application code behind them, not Active Support's
    frame: for a query, the code that ran it; for a redirect, `send_data`, `send_file`, unpermitted
    parameters, and fragment caching, the line in the action; for Processing, Completed, and CSRF
    warnings, the controller's action; for `rescue_from`, where the exception was raised; for a
    render, the code that called `render`, or the template that rendered a partial; for Active Job,
    the code that enqueued or performed the job, or else the job's `#perform`; for Action Mailer,
    the code that delivered the mail, or else the mailer's action; for an exception that a request
    raised, including in a live or streamed response, where the application raised it.
  - Application code that only wraps what Rails runs, such as an `around_action`, or a worker's
    middleware, is not taken for the code behind an entry that Rails logs once it has taken over.
    The search stops where Rails dispatches an action, and where Active Job performs a job from its
    queue, so a template that Rails renders once the action has returned records no call site, and
    a job that a worker performs records its `#perform`, as does a job performed by the inline or
    test adapter. An action, or `#perform`, that a class inherits is labelled with the class that
    defines it, and a compiled template's frame has no label, since Rails names its method with
    numbers that change on every boot. With `BACKTRACE` set, every frame is the application's, so
    the call site is the first frame outside Rails Semantic Logger.
  - Entries with no application code behind them record no call site: Rack's `Started`, a halted
    filter chain, Sidekiq's job start, completion, and error handler entries, and Solid Queue's.
- Active Record: decide whether to log a query's backtrace by its entry's level, `:debug`, as
  Semantic Logger does, rather than the logger's level. With the logger at `:trace` and
  `SemanticLogger.backtrace_level = :debug`, the backtrace started in Active Support rather than at
  the application code that ran the query.
- Sidekiq: log a queue latency (`sidekiq.queue.latency`) of zero, rather than a negative one, when the
  job was enqueued by a host whose clock is ahead of this one. Semantic Logger 5.3 deprecates a
  negative `metric_amount`.

## [5.2.0] - 2026-09-05

- Deprecations: the gem's deprecator is now registered as
  `Rails.application.deprecators[:rails_semantic_logger]`, so the application's own deprecation
  settings govern it: `config.active_support.report_deprecations = false`,
  `config.active_support.deprecation = :raise`, or silencing that one deprecator by name. Rails'
  `active_support.deprecation_behavior` initializer only reaches deprecators in that collection, and
  this one was never added to it, so nothing an application configured could reach the warnings.
  Note that an application still setting deprecated options will now see them raise under
  `config.active_support.deprecation = :raise`.
- Deprecations: the warnings for the deprecated appender options (`format`, `ap_options`, `filter`,
  `console_logger`, `add_file_appender`) are no longer emitted from the setter. Those options are
  documented to be set in `config/application.rb` or `config/environments/*.rb`, which Rails reads in
  `load_environment_config`, long before `active_support.deprecation_behavior` applies the settings
  above, so warning from the setter landed in a window that no application configuration could
  reach. The warnings are now recorded and emitted once Rails has applied that configuration. Each
  option is reported once per boot, attributed to the first place it was set; options set later
  (from `config/initializers/*`, or at runtime) still warn immediately at their call site. Fixes
  #328.
- ActionCable: resolve the `TaggedLoggerProxy` class at runtime instead of requiring it by path.
  Rails 8.2 moves it from `ActionCable::Connection::TaggedLoggerProxy` to
  `ActionCable::Server::TaggedLoggerProxy`, as part of the `ActionCable::Server::Socket` refactor,
  and leaves no back-compat alias, so the unconditional
  `require "action_cable/connection/tagged_logger_proxy"` raised `LoadError` during
  `after_initialize` and failed the app's boot on Rails edge. Fixes #326.
- Documentation: the Semantic Logger documentation site has moved from `logger.rocketjob.io` to
  `logger.reidmorrison.com`. The gem's `homepage` and `documentation_uri` metadata now point there,
  as do the links in the README.

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
