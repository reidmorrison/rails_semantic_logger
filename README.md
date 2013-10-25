rails_semantic_logger
=====================

Improved logging for Ruby on Rails

* http://github.com/ClarityServices/rails_semantic_logger

## Overview

Rails Semantic Logger replaces the Rails default logger with [Semantic Logger](http://github.com/ClarityServices/semantic_logger)

[Semantic Logger](http://github.com/ClarityServices/semantic_logger) takes
logging in Ruby to a new level by adding several new capabilities to the
commonly used Logging API:

Dynamic

* Increase the log level at runtime for just one class
* For example enable debug level logging for a single class (logging instance)
  while the program is running to get more detailed logging in production for just that class

Tagged Logging

* Supply custom data to be added to every log entry within a block of code,
  including libraries and existing gems
* Tagged logging is critical for any high traffic site so that one can narrow
  down log entries for a single call that is mixed in with log entries
  from hundreds of other log entries

High Performance

* Logging is performed in a separate thread so as not to impact performance of
  running code

Customizable

* Custom formatting by destination
* Easy to "roll your own" destination (Appender).
  For example to log to Hadoop, Redis, etc..

Payload support

* Aside from the regular log message, a hash payload can also be supplied with
  every log entry
* Very powerful when logging to NOSQL destinations that allow queries against
  any data in the payload

Exceptions

* Directly log exceptions
* Semantic Logger standardizes the logging of exceptions with their backtraces
  to text destinations and writes the exception elements as a hash to NOSQL
  destinations

Drop-in Replacement

* Simple drop-in replacement for the Ruby, or the Rails loggers
* Supports current common logging interface
* No changes to existing to code to use new logger ( other than replacing the logger )

Rails 2, 3 & 4 Support

* Just include the semantic_logger gem into Rails and it will immediately
  replace the existing loggers to improve performance and information
  in the log files
* The Rails 3 Tagged logging feature is already available for Rails 2 by using Semantic Logger
* Rails 4 push_tags and pop_tags methods are supported

Thread Aware

* Includes the process and thread id information in every log entry
* If running JRuby it will also include the name of the thread for every log entry

Trace Level

* :trace is a new level common in other languages and is commonly used for
  logging trace level detail. It is intended for logging data at level below
  :debug.
* :trace can be used for logging the actual data sent or received over the network
  that is rarely needed but is critical when things are not working as expected.
* Since :trace can be enabled on a per class basis it can even be turned on
  in production to resolve what was actually sent to an external vendor

Multiple Destinations

* Log to multiple destinations at the same time ( File and MongoDB, etc.. )
* Each destination can also have its own log level.
  For example, only log :info and above to MongoDB, or :warn and above to a
  second log file

Benchmarking

* The performance of any block of code can be measured and logged at the same time
  depending on the active log level

Semantic Capabilities

* With Semantic Logger it is simple to mix-in additional semantic information with
every log entry
* The application or class name is automatically included for every log entry under
  a specific logging instance
* Includes the duration of blocks of code
* Any hash containing context specific information such as user_id or location information

Beyond Tagged Logging

* Supply entire hash of custom data to be added to the payload of every log entry
  within a block of code, including libraries and existing gems

NOSQL Destinations

* Every log entry is broken down into elements that NOSQL data stores can understand:

```json
{
    "_id" : ObjectId("5034fa48e3f3fea945e83ef2"),
    "time" : ISODate("2012-08-22T15:27:04.409Z"),
    "host_name" : "release",
    "pid" : 16112,
    "thread_name" : "main",
    "name" : "UserLocator",
    "level" : "debug",
    "message" : "Fetch user information",
    "duration" : 12,
    "payload" : {
        "user" : "Jack",
        "zip_code" : 12345,
        "location" : "US"
    }
}
```

Thread Safe

* Semantic Logger is completely thread safe and all methods can be called
  concurrently from any thread
* Tagged logging keeps any tagging data on a per-thread basis to ensure that
  tags from different threads are not inter-mingled

## Introduction

Just by including the rails_semantic_logger gem, Rails Semantic Logger will
replace the default Rails logger with Semantic Logger. Without further
configuration it will log to the existing Rails log file in a more efficient
multi-threaded way.

Extract from a Rails log file after adding the semantic_logger gem:

```
2012-10-19 12:05:46.736 I [35940:JRubyWorker-10] Rails --

Started GET "/" for 127.0.0.1 at 2012-10-19 12:05:46 +0000
2012-10-19 12:05:47.318 I [35940:JRubyWorker-10] ActionController --   Processing by AdminController#index as HTML
2012-10-19 12:05:47.633 D [35940:JRubyWorker-10] ActiveRecord --   User Load (2.0ms)  SELECT `users`.* FROM `users` WHERE `users`.`id` = 1 LIMIT 1
2012-10-19 12:05:49.833 D [35940:JRubyWorker-10] ActiveRecord --   Role Load (2.0ms)  SELECT `roles`.* FROM `roles`
2012-10-19 12:05:49.868 D [35940:JRubyWorker-10] ActiveRecord --   Role Load (1.0ms)  SELECT * FROM `roles` INNER JOIN `roles_users` ON `roles`.id = `roles_users`.role_id WHERE (`roles_users`.user_id = 1 )
2012-10-19 12:05:49.885 I [35940:JRubyWorker-10] ActionController -- Rendered menus/_control_system.html.erb (98.0ms)
2012-10-19 12:05:51.014 I [35940:JRubyWorker-10] ActionController -- Rendered layouts/_top_bar.html.erb (386.0ms)
2012-10-19 12:05:51.071 D [35940:JRubyWorker-10] ActiveRecord --   Announcement Load (20.0ms)  SELECT `announcements`.* FROM `announcements` WHERE `announcements`.`active` = 1 ORDER BY created_at desc
2012-10-19 12:05:51.072 I [35940:JRubyWorker-10] ActionController -- Rendered layouts/_announcement.html.erb (26.0ms)
2012-10-19 12:05:51.083 I [35940:JRubyWorker-10] ActionController -- Rendered layouts/_flash.html.erb (4.0ms)
2012-10-19 12:05:51.109 I [35940:JRubyWorker-10] ActionController -- Rendered layouts/_footer.html.erb (16.0ms)
2012-10-19 12:05:51.109 I [35940:JRubyWorker-10] ActionController -- Rendered admin/index.html.erb within layouts/base (1329.0ms)
2012-10-19 12:05:51.113 I [35940:JRubyWorker-10] ActionController -- Completed 200 OK in 3795ms (Views: 1349.0ms | ActiveRecord: 88.0ms | Mongo: 0.0ms)
```

## Logging API

### Standard Logging methods

The Semantic Logger logging API supports the existing logging interface for
the Rails and Ruby Loggers. For example:

```ruby
logger.info("Hello World")
```

Or to query whether a specific log level is set

```ruby
logger.info?
```

The following logging methods are available

```ruby
trace(message, payload=nil, exception=nil, &block)
debug(message, payload=nil, exception=nil, &block)
info(message, payload=nil, exception=nil, &block)
warn(message, payload=nil, exception=nil, &block)
error(message, payload=nil, exception=nil, &block)
fatal(message, payload=nil, exception=nil, &block)
```

Parameters

- message: The text message to log.
  Mandatory only if no block is supplied
- payload: Optional, either a Ruby Exception object or a Hash
- exception: Optional, Ruby Exception object. Allows both an exception and a payload to be logged
- block:   The optional block is executed only if the corresponding log level
  is active. Can be used to prevent unnecessary calculations of debug data in
  production.

Examples:

```ruby
logger.debug("Calling Supplier")

logger.debug("Calling Supplier", :request => 'update', :user => 'Jack')

logger.debug { "A total of #{result.inject(0) {|sum, i| i+sum }} were processed" }
```

## Exceptions

The Semantic Logger adds an optional parameter to the existing log methods so that
a corresponding Exception can be logged in a standard way

```ruby
begin
  # ... Code that can raise an exception
rescue Exception => exception
  logger.error("Oops external call failed", exception)
  # Re-raise or handle the exception
  raise exception
end
```

### Payload

The Semantic Logger adds an extra parameter to the existing log methods so that
additional payload can be logged, such as a Hash or a Ruby Exception object.

```ruby
logger.info("Oops external call failed", :result => :failed, :reason_code => -10)
```

The additional payload is machine readable so that we don't have to write complex
regular expressions so that a program can analyze log output. With the MongoDB
appender the payload is written directly to MongoDB as part of the document and
is therefore fully searchable

### Benchmarking

Another common logging requirement is to measure the time it takes to execute a block
of code based on the log level. For example:

```ruby
Rails.logger.benchmark_info "Calling external interface" do
  # Code to call external service ...
end
```

The following output will be written to file:

    2012-08-30 15:37:29.474 I [48308:ScriptThreadProcess: script/rails] (5.2ms) Rails -- Calling external interface

If an exception is raised during the block the exception is logged
at the same log level as the benchmark along with the duration and message.
The exception will flow through to the caller unchanged

The following benchmarking methods are available

```ruby
benchmark_trace(message, params=nil, &block)
benchmark_debug(message, params=nil, &block)
benchmark_info(message, params=nil, &block)
benchmark_warn(message, params=nil, &block)
benchmark_error(message, params=nil, &block)
benchmark_fatal(message, params=nil, &block)
```

Parameters

- message: The mandatory text message to log.
- params:
```
  :log_exception
    Control whether or how an exception thrown in the block is
    reported by Semantic Logger. Values:
    :full
      Log the exception class, message, and backtrace
    :partial
      Log the exception class and messag
      The backtrace will not be logged
    :off
      Any unhandled exception from the block will not be logged

  :min_duration
    Only log if the block takes longer than this duration in ms
    Default: 0.0

  :payload
    Optional, Hash payload

  :exception
    Optional, Ruby Exception object to log along with the duration of the supplied block
```

### Logging levels

The following logging levels are available through Semantic Logger

    :trace, :debug, :info, :warn, :error, :fatal

The log levels are listed above in the order of precedence with the most detail to the least.
For example :debug would include :info, :warn, :error, :fatal levels but not :trace
And :fatal would only log :fatal error messages and nothing else

:unknown has been mapped to :fatal for Rails and Ruby Logger

:trace is a new level that is often used for tracing low level calls such
as the data sent or received to external web services. It is also commonly used
in the development environment for low level trace logging of methods calls etc.

If only the rails logger is being used, then :trace level calls will be logged
as debug calls only if the log level is set to trace

### Changing the Class name for Log Entries

When Semantic Logger is included in a Rails project it automatically replaces the
loggers for Rails, ActiveRecord::Base, ActionController::Base, and ActiveResource::Base
with wrappers that set their Class name. For example:

```ruby
ActiveRecord::Base.logger = SemanticLogger::Logger.new(ActiveRecord)
```

By replacing their loggers we now get the class name in the text logging output:

    2012-08-30 15:24:13.439 D [47900:main] ActiveRecord --   SQL (12.0ms)  SELECT `schema_migrations`.`version` FROM `schema_migrations`

It is recommended to include a class specific logger for all major classes that will
be logging using the SemanticLogger::Loggable mix-in. For Example:

```ruby
require 'semantic_logger'

class ExternalSupplier
  # Lazy load logger class variable on first use
  include SemanticLogger::Loggable

  def call_supplier(amount, name)
    logger.debug "Calculating with amount", { :amount => amount, :name => name }

    # Measure and log on completion how long the call took to the external supplier
    logger.benchmark_info "Calling external interface" do
      # Code to call the external supplier ...
    end
  end
end
```

This will result in the log output identifying the log entry as from the ExternalSupplier class

    2012-08-30 15:37:29.474 I [48308:ScriptThreadProcess: script/rails] (5.2ms) ExternalSupplier -- Calling external interface

### Tagged Logging

Semantic Logger allows any Ruby or Rails program to also include tagged logging.

This means that any logging performed within a block, including any called
libraries or gems to include the specified tag with every log entry.

Using Tagged logging is critical in any highly concurrent environment so that
one can quickly find all related log entries across all levels of code, and even
across threads

```ruby
logger.tagged(tracking_number) do
  logger.debug("Hello World")
  # ...
end
```

### Beyond Tagged Logging

Blocks of code can be tagged with not only values, but can be tagged with
entire hashes of data. The additional hash of data will be merged into
the payload of every log entry

For example every corresponding log entry could include a hash containing
a user_id, name, region, zip_code, tracking_number, etc...

```ruby
logger.with_payload(:user => 'Jack', :zip_code => 12345) do
  logger.debug("Hello World")
  # ...
end
```

### Installation

Add the following line to Gemfile

```ruby
gem 'rails_semantic_logger'
```

Install required gems with bundler

    bundle install

This will automatically replace the standard Rails logger with Semantic Logger
which will write all log data to the configured Rails logger.

### Configuration

By default Semantic Logger will detect the log level from Rails. To set the
log level explicitly, add the following line to
config/environments/production.rb inside the Application.configure block

```ruby
config.log_level = :trace
```

#### MongoDB logging

To log to both the Rails log file and MongoDB add the following lines to
config/environments/production.rb inside the Application.configure block

```ruby
config.after_initialize do
  # Re-use the existing MongoDB connection, or create a new one here
  db = Mongo::Connection.new['production_logging']

  # Besides logging to the standard Rails logger, also log to MongoDB
  config.semantic_logger.add_appender SemanticLogger::Appender::MongoDB.new(
    :db              => db,
    :collection_name => 'semantic_logger',
    :collection_size => 25.gigabytes
  )
end
```

#### Logging to Syslog

Configuring rails to also log to a local Syslog:
```ruby
config.after_initialize do
  config.semantic_logger.add_appender(SemanticLogger::Appender::Syslog.new)
end
```

Configuring rails to also log to a remote Syslog server such as syslog-ng over TCP:
```ruby
config.after_initialize do
  config.semantic_logger.add_appender(SemanticLogger::Appender::Syslog.new(:server => 'tcp://myloghost:514'))
end
```

#### Colorized Logging

If the Rails colorized logging is enabled, then the colorized formatter will be used
by default. To disable colorized logging in both Rails and SemanticLogger:

```ruby
config.colorize_logging = false
```

## Custom Appenders and Formatters

To write your own appenders or formatting, see [SemanticLogger](http://github.com/ClarityServices/semantic_logger)

## Log Rotation

Since the log file is not re-opened with every call, when the log file needs
to be rotated, use a copy-truncate operation rather than deleting the file.

## Dependencies

- Ruby MRI 1.8.7, 1.9.3 (or above) Or, JRuby 1.6.3 (or above)
- Rails 2, 3, 4 or above

Meta
----

* Code: `git clone git://github.com/ClarityServices/rails_semantic_logger.git`
* Home: <https://github.com/ClarityServices/rails_semantic_logger>
* Bugs: <http://github.com/ClarityServices/rails_semantic_logger/issues>
* Gems: <http://rubygems.org/gems/rails_semantic_logger>

This project uses [Semantic Versioning](http://semver.org/).

Author
------

Reid Morrison :: reidmo@gmail.com :: @reidmorrison

Contributors
------------

Marc Bellingrath :: marrrc.b@gmail.com

License
-------

Copyright 2012,2013 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
