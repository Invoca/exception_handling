# frozen_string_literal: true

require 'action_mailer'

module ExceptionHandling
  class Mailer < ActionMailer::Base
    default content_type: "text/html"

    append_view_path "#{File.dirname(__FILE__)}/../../views"

    [:email_environment, :server_name, :sender_address, :exception_recipients, :escalation_recipients].each do |method|
      define_method method do
        ExceptionHandling.send(method) or raise "No #{method} set!"
      end
    end

    def email_prefix
      "#{email_environment} exception: "
    end

    class << self
      def reloadable?
        false
      end

      def mailer_method_category
        {
          log_parser_exception_notification: :NetworkOptout
        }
      end
    end

    def escalation_notification(summary, data)
      subject       = "#{email_environment} Escalation: #{summary}"
      from          = sender_address.gsub('xception', 'scalation')
      recipients    = begin
                        escalation_recipients
                      rescue
                        exception_recipients
                      end

      @summary      = summary
      @server       = ExceptionHandling.server_name
      @cleaned_data = data

      mail(from: from,
           to: recipients,
           subject: subject)
    end

    def escalate_custom(summary, data, recipients)
      subject       = "#{email_environment} Escalation: #{summary}"
      from          = sender_address.gsub('xception', 'scalation')
      recipients    = recipients

      @summary      = summary
      @server       = ExceptionHandling.server_name
      @cleaned_data = data

      mail(from: from,
           to: recipients,
           subject: subject)
    end

    def log_parser_exception_notification(cleaned_data, key)
      if cleaned_data.is_a?(Hash)
        cleaned_data = cleaned_data.symbolize_keys
        local_subject = cleaned_data[:error]
      else
        local_subject = "#{key}: #{cleaned_data}"
        cleaned_data  = { error: cleaned_data.to_s }
      end

      @subject       = "#{email_prefix}#{local_subject}"[0, 300]
      @recipients    = exception_recipients
      from           = sender_address
      @cleaned_data  = cleaned_data

      mail(from: from,
           to: @recipients,
           subject: @subject)
    end
  end
end
