# ExceptionHandling

Enable emails for your exceptions that occur in your application!

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

    require "exception_handling"

    # required
    ExceptionHandling.server_name             = Cluster['server_name']
    ExceptionHandling.sender_address          = %("Exceptions" <exceptions@example.com>)
    ExceptionHandling.exception_recipients    = ['exceptions@example.com']
    ExceptionHandling.logger                  = Rails.logger

    # optional
    ExceptionHandling.escalation_recipients   = ['escalation@example.com']
    ExceptionHandling.mailer_send_enabled     = true # false, will disable exception emails
    ExceptionHandling.filter_list_filename    = "#{Rails.root}/config/exception_filters.yml"
    ExceptionHandling.email_environment       = Rails.env
    ExceptionHandling.eventmachine_safe       = false
    ExceptionHandling.eventmachine_synchrony  = false


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

## Custom Data

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


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
