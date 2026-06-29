# Rails Semantic Logger
[![Gem Version](https://img.shields.io/gem/v/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![Build Status](https://github.com/reidmorrison/rails_semantic_logger/workflows/build/badge.svg)](https://github.com/reidmorrison/rails_semantic_logger/actions?query=workflow%3Abuild) [![Downloads](https://img.shields.io/gem/dt/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Rails Semantic Logger replaces the Rails default logger with [Semantic Logger](https://logger.rocketjob.io/).

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
      config.rails_semantic_logger.appenders do |appenders|
        appenders.add(io: $stdout, formatter: :json)
      end
    end
~~~

Declaring an appender this way automatically replaces the default `log/<env>.log` file appender, so JSON to stdout becomes the only destination. See [Configuring appenders](https://logger.rocketjob.io/rails) for the full guide.

Once logs are emitted as structured JSON, a centralized logging system can parse them into a searchable hierarchy. Each field, including the nested `payload` and any `metric` data, becomes directly queryable, so you can build searches, alerts, and dashboards against well-defined fields instead of brittle text matching. See the [documentation](https://logger.rocketjob.io/rails) for worked examples of parsing the JSON and building queries and dashboards.

## Documentation

For complete documentation see: https://logger.rocketjob.io/rails

## Upgrading

The way appenders (log destinations) are configured changed in v5. See the
[v4 to v5 migration guide](https://logger.rocketjob.io/rails#migrating-from-v4-to-v5) for the
before/after mapping, and [Upgrading from earlier versions](https://logger.rocketjob.io/rails#migrating-from-earlier-versions)
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
