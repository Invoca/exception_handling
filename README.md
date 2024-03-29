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
ExceptionHandling.logger                  = Rails.logger

# optional
ExceptionHandling.filter_list_filename    = "#{Rails.root}/config/exception_filters.yml"
ExceptionHandling.environment             = Rails.env
ExceptionHandling.honeybadger_auto_tagger = ->(exception) { [] } # See "Automatically Tagging Exceptions" section below for examples
ExceptionHandling.add_honeybadger_tag_from_log_context("tag-name", path: ["path", "in", "log", "context"])
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

⚠️ Honeybadger differentiates tags by spaces and/or commas, so you should **not** include spaces or commas in your tags.

⚠️ Tags are case-sensitive.

#### Manually Tagging Exceptions

Add `:honeybadger_tags` to your `log_context` usage with an array of strings.

```ruby
log_error(ex, "A specific error occurred.", honeybadger_tags: ["critical", "sequoia"])
```

**Note**: Manual tags will be merged with any automatic tags.

#### Automatically Tagging Exceptions via Proc (`honeybadger_auto_tagger=`)

Configure exception handling so that you can automatically apply multiple tags to exceptions sent to honeybadger.

The Proc must accept an `exception` argument that will be the exception in question and must always return an array of strings (the array can be empty).

Example to enable auto-tagging:
```ruby
ExceptionHandling.honeybadger_auto_tagger = ->(exception) do
  exception.message.match?(/fire/) ? ["high-urgency", "danger"] : ["low-urgency"]
end
```

Example to disable auto-tagging:
```ruby
ExceptionHandling.honeybadger_auto_tagger = nil
```

#### Automatically Tagging Exceptions from Log Context (`add_honeybadger_tag_from_log_context`)

Add a tag to exceptions sent to honeybadger based on a value in the log context.

To configure this, use the `add_honeybadger_tag_from_log_context` method.
```ruby
ExceptionHandling.add_honeybadger_tag_from_log_context("kubernetes_context", path: ["kubernetes", "context"])
```

This will add a tag to the exception if the log context contains a value at the specified path: "kubernetes" => { "context" => "value" }.

For example:
```ruby
ExceptionHandling.logger.with_context("kubernetes" => { "context" => "local" }) do
  log_error(ex, "A specific error occurred.")
end
```

This will add the following tag to the exception sent to honeybadger:
```
kubernetes_context:local
```

To clear all automated tagging from the log context, use the `clear_honeybadger_tags_from_log_context` method.
```ruby
ExceptionHandling.clear_honeybadger_tags_from_log_context
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
