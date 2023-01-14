# ExceptionHandling

Enable emails for your exceptions that occur in your application!

## Dependencies
- Ruby 2.6
- Rails >= 4.2, < 7

## Installation

Add this line to your application's Gemfile:

    gem 'exception_handling'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install exception_handling

## Setup

Add some code to initialize the settings in your application.
For example:

```ruby
require "exception_handling"

# required
ExceptionHandling.server_name             = Cluster['server_name']
ExceptionHandling.sender_address          = %("Exceptions" <exceptions@example.com>)
ExceptionHandling.exception_recipients    = ['exceptions@example.com']
ExceptionHandling.logger                  = Rails.logger

# optional
ExceptionHandling.escalation_recipients   = ['escalation@example.com']
ExceptionHandling.filter_list_filename    = "#{Rails.root}/config/exception_filters.yml"
ExceptionHandling.email_environment       = Rails.env
ExceptionHandling.eventmachine_safe       = false
ExceptionHandling.eventmachine_synchrony  = false
ExceptionHandling.sensu_host              = "127.0.0.1"
ExceptionHandling.sensu_port              = 3030
ExceptionHandling.sensu_prefix            = ""
ExceptionHandling.honeybadger_filepath_tagger        = {} # See "Automatically Tagging Exceptions" section below for specific examples
ExceptionHandling.honeybadger_exception_class_tagger = {} # See "Automatically Tagging Exceptions" section below for specific examples
```

## Usage

Mixin the `ExceptionHandling::Methods` module into your controllers, models or classes. The example below adds it to all the controllers in you rails application:

    class ApplicationController < ActionController::Base
      include ExceptionHandling::Methods
      ...
    end

Then call any method available in the `ExceptionHandling::Methods` mixin:

    begin
      ...
    rescue => ex
      log_error( ex, "A specific error occurred." )
      flash.now['error'] = "A specific error occurred. Support has been notified."
    end

### Tagging Exceptions in Honeybadger

#### Manually Tagging Exceptions

Add `:honeybadger_tags` to your `log_context` usage with an array of strings.

```ruby
log_error(ex, "A specific error occurred.", honeybadger_tags: ["critical", "sequoia"])
```

**Note**: Manual tags will be merged with any automatic tags.

#### Automatically Tagging Exceptions

Configure exception handling so that you can automatically apply multiple tags to exceptions sent to honeybadger.

##### Auto Tag by File Paths in the Exception Backtrace (`honeybadger_filepath_tagger=`)

- The key is the tag name to be auto-tagged and the corresponding value array is the file path patterns that are cross referenced against the exception's backtrace for a match.
    - If any file in the backtrace matches, the tag will be applied.
    - Ruby gem paths will be ignored.
- Multiple tags can be applied to the same exception.
- Specific line numbers are not supported.
- Any tags assigned by filepathwill be merged with any tags matched by exception class, if also using the `honeybadger_exception_class_tagger`.

⚠️ **The performance of the auto-tagger is directly correlated to the size of the config. The larger the config is, the worse the potential performance impact may be. Tread lightly.**

Example static config:
```ruby
ExceptionHandling.honeybadger_filepath_tagger = {
  "cereals" => [
    "app/models/captain_crunch.rb", # Files can be the full file path
    "app/models/cocoa_puffs.rb"
  ],
  "ivr-campaigns-team" => [
    "app/models/user" # Filepaths that are not the full path may have multiple filepaths match (e.g. user.rb and username.rb)
  ],
  "critical" => [
    "app/models/user.rb" # It's ok to have overlaps, in this example an exception with `app/models/user.rb` in the backtrace will have "ivr-campaigns-team" and "critical" applied as tags.
  ]
  "external-api" => [
    "lib/inteliquent/.*" # Regular expressions can be used to encapsulate entire folders
  ]
}
```

Example dynamic config:

- This allows for the tag config to be defined dynamically, meaning you don't need to deploy or restart your service in order to change the tagging config.
    - The expected shape of the return value of the Proc is the same as the static config example above.
    - On every exception sent to Honeybadger the tagger will be regenerated based on the config hash returned from the Proc.
- If the Proc raises an exception, no tags will be marked.
- ⚠️ **WARNING**: Using a dynamic config will obviously have worse performance than static config. How much the performance will be affected is not exactly known.
- ⚠️ **WARNING**: If using ProcessSettings, ensure your ProcessSettings changes have been defined, reviewed, and deployed before applying a dynamic config like the example below.

```ruby
ExceptionHandling.honeybadger_filepath_tagger = -> { ProcessSettings["web", "honeybadger_filepath_tagger_config"] }
```

##### Auto Tag by Exception Class (`honeybadger_exception_class_tagger=`)
- The key is the tag name to be auto-tagged and the corresponding value array is the exception classes or names that match the exception.
    - Only exact classes will be matched. Exception inheritance will not be checked.
- Exception class names must match the full class path (e.g. "Inteliquent::Api::ApiHelper::ResponseCodeError").
- Any tags assigned by exception class will be merged with any tags matched by filepath, if also using the `honeybadger_filepath_tagger`.

⚠️ **The performance of the auto-tagger is directly correlated to the size of the config. The larger the config is, the worse the potential performance impact may be. Tread lightly.**

Example static config:
```ruby
ExceptionHandling.honeybadger_exception_class_tagger = {
  "cereals" => [
    "Cereals::CaptainCrunchException",
    "Cereals::CocoaPuffsException",
    ExampleStringNamedError
  ],
  "ivr-campaigns-team" => [
    "SomeOtherErrorClass",
    "RuntimeError"
  ],
  "calls-team" => [
    "AnotherClass::SomeCallsSpecificException",
    "ExampleStringNamedError",
    RuntimeError
  ]
}
```

Example dynamic config:

- This allows for the tag config to be defined dynamically, meaning you don't need to deploy or restart your service in order to change the tagging config.
    - The expected shape of the return value of the Proc is the same as the static config example above.
    - On every exception sent to Honeybadger the tagger will be regenerated based on the config hash returned from the Proc.
- If the Proc raises an exception, no tags will be marked.
- ⚠️ **WARNING**: Using a dynamic config will obviously have worse performance than static config. How much the performance will be affected is not exactly known.
- ⚠️ **WARNING**: If using ProcessSettings, ensure your ProcessSettings changes have been defined, reviewed, and deployed before applying a dynamic config like the example below.

```ruby
ExceptionHandling.honeybadger_exception_class_tagger = -> { ProcessSettings["web", "honeybadger_exception_class_tagger_config"] }
```

## Custom Hooks

### custom_data_hook

Emails are generated using the `.erb` templates in the [views](./views) directory.  You can add custom information to the exception data with a custom method. For example:

    def append_custom_user_info(data)
      begin
        data[:user_details]                = {}
        data[:user_details][:username]     = "CaryP"
        data[:user_details][:organization] = "Invoca Engineering Dept."
      rescue Exception => e
        # don't let these out!
      end
    end

Then tie this in using the `custom_data_hook`:

    ExceptionHandling.custom_data_hook = method(:append_custom_user_info)


### post_log_error_hook

There is another hook available intended for custom actions after an error email is sent.  This can be used to send information about errors to your alerting subsystem.  For example:

    def log_error_metrics(exception_data, exception, treat_like_warning, honeybadger_status)
      if treat_like_warning
        Invoca::Metrics::Client.metrics.counter("exception_handling/warning")
      else
        Invoca::Metrics::Client.metrics.counter("exception_handling/exception")
      end

      case honeybadger_status
      when :success
        Invoca::Metrics::Client.metrics.counter("exception_handling.honeybadger.success")
      when :failure
        Invoca::Metrics::Client.metrics.counter("exception_handling.honeybadger.failure")
      when :skipped
        Invoca::Metrics::Client.metrics.counter("exception_handling.honeybadger.skipped")
      end
    end
    ExceptionHandling.post_log_error_hook = method(:log_error_metrics)


## Testing

There is a reusable rails controller stub that might be useful for your own tests.  To leverage it in your own test, simply add the following require to your unit tests:

        require 'exception_handling/testing'

We use it for testing that our `custom_data_hook` code is working properly.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
