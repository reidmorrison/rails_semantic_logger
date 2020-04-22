# Rails Semantic Logger
[![Gem Version](https://img.shields.io/gem/v/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![Build Status](https://travis-ci.org/rocketjob/rails_semantic_logger.svg?branch=master)](https://travis-ci.org/rocketjob/rails_semantic_logger) [![Downloads](https://img.shields.io/gem/dt/rails_semantic_logger.svg)](https://rubygems.org/gems/rails_semantic_logger) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Rails Semantic Logger replaces the Rails default logger with [Semantic Logger](http://github.com/rocketjob/semantic_logger)

* http://github.com/rocketjob/rails_semantic_logger

## Documentation

For complete documentation see: http://rocketjob.github.io/semantic_logger/rails

## Upgrading to Semantic Logger v4.4

With some forking frameworks it is necessary to call `reopen` after the fork. With v4.4 the
workaround for Ruby 2.5 crashes is no longer needed. 
I.e. Please remove the following line if being called anywhere:

~~~ruby
SemanticLogger::Processor.instance.instance_variable_set(:@queue, Queue.new)
~~~

## Supports

For the complete list of supported Ruby and Rails versions, see the [Testing file](https://github.com/rocketjob/rails_semantic_logger/blob/master/.travis.yml).

## Author

[Reid Morrison](https://github.com/reidmorrison)

[Contributors](https://github.com/rocketjob/rails_semantic_logger/graphs/contributors)

## Versioning

This project uses [Semantic Versioning](http://semver.org/).
