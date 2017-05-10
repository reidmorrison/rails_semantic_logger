## Installation

Install all needed gems to run the tests:

    appraisal install

The gems are installed into the global gem list.
The Gemfiles in the `gemfiles` folder are also re-generated.

## Run Tests

For all supported Rails/ActiveRecord versions:

    rake

Or for specific rails version:

    appraisal rails_4.2 rake

Or for one particular test file:

    appraisal rails_5.0 ruby test/controllers/articles_controller_test.rb 

Or down to one test case:

    appraisal rails_5.0 ruby test/controllers/articles_controller_test.rb  -n "/shows new article/"
