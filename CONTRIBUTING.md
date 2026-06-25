# Contributing

Welcome to Rails Semantic Logger, great to have you on-board. :tada:

To get you started here are some pointers.

## Open Source

#### Early Adopters

Great to have you onboard, looking forward to your help and feedback.

#### Late Adopters

Rails Semantic Logger is open source, maintained by the author and contributors in their spare time and
offered to the community free of charge. Please keep that in mind when raising issues or requesting features,
since there is no dedicated team available to take on custom work on demand.

If you have a specific need, particularly an edge case that is unique to your own environment or job, the
best way forward is to implement it yourself and open a Pull Request. Contributions of this kind are exactly
how the project grows, and they are warmly welcomed and appreciated.

## Documentation

Documentation updates are welcome and appreciated by all users of Rails Semantic Logger.

The user-facing documentation for this gem does **not** live in this repository. It lives in the companion
[Semantic Logger](https://github.com/reidmorrison/semantic_logger) repository, as a Jekyll site under its
`docs` subdirectory, published to [logger.rocketjob.io](https://logger.rocketjob.io). The Rails specific page
is `docs/rails.md`.

To change the documentation, follow the documentation instructions in the `CONTRIBUTING.md` of the
`semantic_logger` repository and edit `docs/rails.md` there.

## Code Changes

Since changes cannot be made directly to the Rails Semantic Logger repository, fork it to your own account on
Github.

1. Fork the repository in github.
2. Clone the repository to your local machine.
3. Change into the Rails Semantic Logger directory.

       cd rails_semantic_logger

4. Install required gems.

   Tests run via [Appraisal](https://github.com/thoughtbot/appraisal) across multiple Rails versions, so
   install the gems for every appraisal. This regenerates the gemfiles under `gemfiles/`.

       bundle install
       bundle exec appraisal install

5. Run tests.

   The default rake task runs the tests against every supported Rails version (each appraisal):

       bundle exec rake

   To run the tests once against the current `Gemfile`:

       bundle exec rake test

   To run the tests against a single Rails version:

       bundle exec appraisal rails_8.0 rake

   To run a single test file, or a single test by name:

       bundle exec appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb
       bundle exec appraisal rails_8.0 ruby test/controllers/articles_controller_test.rb -n "/shows new article/"

   Set the `BACKTRACE` environment variable to get full backtraces in the test output.

6. Run the linter.

       bundle exec rubocop

   The minimum supported Ruby is 3.2, and the minimum supported Rails is 7.2, so please do not use syntax or
   APIs newer than that under `lib`.

7. When making a bug fix it is recommended to update the test first, ensure the test fails, and only then
   make the code fix.

8. Once the tests pass and all code changes are complete, commit the changes.

9. Push changes to your forked repository.

10. Submit a Pull Request back to the Rails Semantic Logger repository.

## Philosophy

Rails Semantic Logger adapts Rails to [Semantic Logger](https://logger.rocketjob.io/). It
**monkey-patches Rails to replace its loggers and log subscribers with Semantic Logger**, so that Rails
produces structured logs directly instead of human-readable text that downstream systems have to parse.

Rather than parsing Rails' text output (`Started`, `Processing`, `Completed`, `Rendered`, `SQL`, and so on),
this gem reimplements the built-in `ActiveSupport::LogSubscriber`s (and replaces other loggers) wherever
possible, emitting a message plus a structured payload that can be rendered as text, color, or JSON for
centralized logging.

This gem only adapts Rails to Semantic Logger. The actual logging engine, appenders, and formatters live in
the separate `semantic_logger` gem, which is a runtime dependency. The two libraries are kept in lock step at
the major-version level, so a breaking change in `semantic_logger` is paired with a matching
`rails_semantic_logger` major version.

## Architecture

### The core maintenance challenge: tracking Rails' log subscribers

Rails' own log subscribers change between Rails versions, sometimes even in minor or patch releases. Because
this gem reimplements those subscribers to emit structured payloads, that coupling makes it **inherently
brittle**. The central, recurring maintenance task is:

1. Look at the log subscriber source for each supported Rails version (ActionController, ActionView,
   ActiveRecord, ActiveJob, ActionMailer, and others).
2. Bring any upstream changes across into this gem's corresponding subscriber under
   `lib/rails_semantic_logger/<component>/log_subscriber.rb`.
3. Replace the upstream **text** output with **hash / structured** logging (message plus payload) while
   preserving the new behavior.

When touching a subscriber, diff it against the matching Rails version's subscriber to confirm parity.

### Engine bootstrap (`lib/rails_semantic_logger/engine.rb`)

This is the heart of the gem and the most important file to understand. The `Engine`:

- Exposes two config namespaces on the Rails app: `config.semantic_logger` (the `SemanticLogger` module
  itself) and `config.rails_semantic_logger` (a `RailsSemanticLogger::Options` instance).
- **Deletes** Rails' built-in `:initialize_logger` initializer and replaces it with its own. The replacement
  sets `SemanticLogger.default_level` from `config.log_level`, swaps the `Rails::Rack::Logger` middleware for
  `RailsSemanticLogger::Rack::Logger`, builds the file appender (`log/<env>.log`), and assigns `Rails.logger`.
  If the log file cannot be opened, it degrades gracefully to STDERR at `:warn`.
- Uses `ActiveSupport.on_load(...)` hooks to mix `SemanticLogger::Loggable` into `active_record`,
  `action_controller`, `action_mailer`, and `action_view`, and sets the ActionCable logger.
- In `config.before_initialize` / `config.after_initialize`, replaces loggers for optional integrations when
  their constants are defined: Mongoid/Moped/Mongo, Resque, Sidekiq, SolidQueue, Delayed Job,
  ActiveModelSerializers.

### Log subscribers (`lib/rails_semantic_logger/<component>/log_subscriber.rb`)

Each Rails component subscriber (action_controller, action_view, active_record, active_job, action_mailer,
solid_queue) is a custom `ActiveSupport::LogSubscriber` that translates `ActiveSupport::Notifications` events
into semantic log entries with payloads instead of formatted strings. The engine installs these via
`RailsSemanticLogger.swap_subscriber(old_class, new_class, notifier)` in `lib/rails_semantic_logger.rb`, which
detaches Rails' default subscribers (handling the Rails-version differences in the notifier listener API)
before attaching ours.

These are the files most affected by the "track Rails' log subscribers" maintenance task described above:
they are reimplementations of upstream Rails subscribers and must be kept in sync with each supported Rails
version.

### Options (`lib/rails_semantic_logger/options.rb`)

`RailsSemanticLogger::Options` is the public configuration surface, set via `config.rails_semantic_logger.*`
in `application.rb`. Key flags include `semantic`, `started`, `processing`, `rendered`, `quiet_assets`,
`add_file_appender`, `format` (`:default` / `:color` / `:json` / class / Proc), `filter`, `ap_options`,
`action_message_format`, `replace_sidekiq_logger`, `replace_solid_queue_logger`, and `console_logger`. The
long comment block at the top of that file is the authoritative documentation for each option, so keep it in
sync when changing defaults or behavior.

### Extensions (`lib/rails_semantic_logger/extensions/`)

Monkey-patches and overrides of third-party and Rails internals, each loaded conditionally on the relevant
constant being defined (for example `extensions/mongoid/config.rb`, `extensions/sidekiq/sidekiq.rb`,
`extensions/active_support/tagged_logging.rb`, `extensions/action_dispatch/debug_exceptions.rb`). These keep
integrations isolated and only activated when the host app uses that library.

### Integration loaders (Sidekiq, Delayed Job, SolidQueue)

Background job integrations live under their own namespaces (`sidekiq/`, `delayed_job/`, `solid_queue/`),
providing job loggers and `Loggable` mixins, and are wired up from the engine only when the corresponding gem
is present.

## Tests

Tests run against a full dummy Rails app in `test/dummy/` (controllers, models, jobs, mailers, sqlite3 DB).
`test/test_helper.rb` boots that app, loads Sidekiq in server mode, and includes `SemanticLogger::Test::Minitest`
helpers. `test/payload_collector.rb` captures emitted log entries so tests can assert on the structured
payload rather than text output; this is the standard pattern for verifying subscriber behavior.

## Contributor Code of Conduct

As contributors and maintainers of this project, and in the interest of fostering an open and welcoming community, we pledge to respect all people who contribute through reporting issues, posting feature requests, updating documentation, submitting pull requests or patches, and other activities.

We are committed to making participation in this project a harassment-free experience for everyone, regardless of level of experience, gender, gender identity and expression, sexual orientation, disability, personal appearance, body size, race, ethnicity, age, religion, or nationality.

Examples of unacceptable behavior by participants include:

* The use of sexualized language or imagery
* Personal attacks
* Trolling or insulting/derogatory comments
* Public or private harassment
* Publishing other's private information, such as physical or electronic addresses, without explicit permission
* Other unethical or unprofessional conduct.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct. By adopting this Code of Conduct, project maintainers commit themselves to fairly and consistently applying these principles to every aspect of managing this project. Project maintainers who do not follow or enforce the Code of Conduct may be permanently removed from the project team.

This code of conduct applies both within project spaces and in public spaces when an individual is representing the project or its community.

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by opening an issue or contacting one or more of the project maintainers.

This Code of Conduct is adapted from the [Contributor Covenant](http://contributor-covenant.org), version 1.2.0, available at [http://contributor-covenant.org/version/1/2/0/](http://contributor-covenant.org/version/1/2/0/)
