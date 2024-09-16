# Rails Semantic Logger
[![Gem Version](https://img.shields.io/gem/v/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![Build Status](https://github.com/reidmorrison/rails_semantic_logger/workflows/build/badge.svg)](https://github.com/reidmorrison/rails_semantic_logger/actions?query=workflow%3Abuild) [![Downloads](https://img.shields.io/gem/dt/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Rails Semantic Logger replaces the Rails default logger with [Semantic Logger](https://logger.rocketjob.io/)

When any large Rails application is deployed to production one of the first steps is to move to centralized logging, so that logs can be viewed and searched from a central location.

Centralized logging quickly falls apart when trying to consume the current human readable log files:
- Log entries often span multiple lines, resulting in unrelated log lines in the centralized logging system. For example, stack traces.
- Complex Regular Expressions are needed to parse the text lines and make them machine readable. For example to build queries, or alerts that are looking for specific elements in the message.
- Writing searches, alerts, or dashboards based on text logs is incredibly brittle, since a small change to the text logged can often break the parsing of those logs.
- Every log entry often has a completely different format, making it difficult to make consistent searches against the data.

For these and many other reasons switching to structured logging, or logs in JSON format, in testing and production makes centralized logging incredibly powerful.

For example, adding these lines to `config/application.rb` and removing any other log overrides from other environments, will switch automatically to structured logging when running inside Kubernetes:
~~~ruby
    # Setup structured logging
    config.semantic_logger.application = "my_application"
    config.semantic_logger.environment = ENV["STACK_NAME"] || Rails.env
    config.log_level = ENV["LOG_LEVEL"] || :info

    # Switch to JSON Logging output to stdout when running on Kubernetes
    if ENV["LOG_TO_CONSOLE"] || ENV["KUBERNETES_SERVICE_HOST"]
      config.rails_semantic_logger.add_file_appender = false
      config.semantic_logger.add_appender(io: $stdout, formatter: :json)
    end
~~~

Then configure the centralized logging system to tell it that the data is in JSON format, so that it will parse it for you into a hierarchy.

For example, the following will instruct [Observe](https://www.observeinc.com/) to parse the JSON data and create machine readable data from it:
~~~ruby
interface "log", "log":log

make_col event:parse_json(log)

make_col
   time:parse_isotime(event.timestamp),
   application:string(event.application),
   environment:string(event.environment),
   duration:duration_ms(event.duration_ms),
   level:string(event.level),
   name:string(event.name),
   message:string(event.message),
   named_tags:event.named_tags,
   payload:event.payload,
   metric:string(event.metric),
   metric_amount:float64(event.metric_amount),
   tags:array(event.tags),
   exception:event.exception,
   host:string(event.host),
   pid:int64(event.pid),
   thread:string(event.thread),
   file:string(event.file),
   line:int64(event.line),
   dimensions:event.dimensions,
   backtrace:array(event.backtrace),
   level_index:int64(event.level_index)

set_valid_from(time)
drop_col timestamp, log, event, stream
rename_col timestamp:time
~~~

Now queries can be built to drill down into each of these fields, including `payload` which is a nested object.

For example to find all failed Sidekiq job calls where the causing exception class name is `NoMethodError`:
~~~ruby
filter environment = "uat2"
filter level = "error"
filter metric = "sidekiq.job.perform"
filter (string(exception.cause.name) = "NoMethodError")
~~~

Example: create a dashboard showing the duration of all successful Sidekiq jobs:
~~~ruby
filter environment = "production"
filter level = "info"
filter metric = "sidekiq.job.perform"
timechart duration:avg(duration), group_by(name)
~~~

Example: create a dashboard showing the queue latency of all Sidekiq jobs. 
The queue latency is the time between when the job was enqueued and when it was started:
~~~ruby
filter environment = "production"
filter level = "info"
filter metric = "sidekiq.queue.latency"
timechart latency:avg(metric_amount/1000), group_by(string(named_tags.queue))
~~~

* http://github.com/reidmorrison/rails_semantic_logger

## Documentation

For complete documentation see: https://logger.rocketjob.io/rails

## Upgrading to Semantic Logger V4.16 - Sidekiq Metrics Support

Rails Semantic Logger now supports Sidekiq metrics. 
Below are the metrics that are now available when the JSON logging format is used:
- `sidekiq.job.perform`
  - The duration of each Sidekiq job.
  - `duration` contains the time in milliseconds that the job took to run.
- `sidekiq.queue.latency` 
  - The time between when a Sidekiq job was enqueued and when it was started.
  - `metric_amount` contains the time in milliseconds that the job was waiting in the queue.

## Upgrading to Semantic Logger v4.15 & V4.16 - Sidekiq Support

Rails Semantic Logger introduces direct support for Sidekiq v4, v5, v6, and v7. 
Please remove any previous custom patches or configurations to make Sidekiq work with Semantic Logger.
To see the complete list of patches being made, and to contribute your own changes, see: [Sidekiq Patches](https://github.com/reidmorrison/rails_semantic_logger/blob/master/lib/rails_semantic_logger/extensions/sidekiq/sidekiq.rb)

## Upgrading to Semantic Logger v4.4

With some forking frameworks it is necessary to call `reopen` after the fork. With v4.4 the
workaround for Ruby 2.5 crashes is no longer needed. 
I.e. Please remove the following line if being called anywhere:

~~~ruby
SemanticLogger::Processor.instance.instance_variable_set(:@queue, Queue.new)
~~~

## New Versions of Rails, etc.

The primary purpose of the Rails Semantic Logger gem is to patch other gems, primarily Rails, to make them support structured logging though Semantic Logger.

When new versions of Rails and other gems are published they often make changes to the internals, so the existing patches stop working.

Rails Semantic Logger survives only when someone in the community upgrades to a newer Rails or other supported libraries, runs into problems, 
and then contributes the fix back to the community by means of a pull request.

Additionally, when new popular gems come out, we rely only the community to supply the necessary patches in Rails Semantic Logger to make those gems support structured logging.

## Supported Platforms

For the complete list of supported Ruby and Rails versions, see the [Testing file](https://github.com/reidmorrison/rails_semantic_logger/blob/master/.github/workflows/ci.yml).

## Author

[Reid Morrison](https://github.com/reidmorrison)

[Contributors](https://github.com/reidmorrison/rails_semantic_logger/graphs/contributors)

## Versioning

This project uses [Semantic Versioning](http://semver.org/).
