require 'action_mailer'

module ExceptionHandling
  class Mailer < ActionMailer::Base
    default :content_type => "text/html"

    self.append_view_path "#{File.dirname(__FILE__)}/../../views"

    [:email_environment, :server_name, :sender_address, :exception_recipients, :escalation_recipients].each do |method|
      define_method method do
        ExceptionHandling.send(method) or raise "No #{method} set!"
      end
    end

    def email_prefix
      "#{email_environment} exception: "
    end

    def self.reloadable?() false end

    def exception_notification( cleaned_data, first_seen_at = nil, occurrences = 0 )
      if cleaned_data.is_a?(Hash)
        cleaned_data.merge!({:occurrences => occurrences, :first_seen_at => first_seen_at}) if first_seen_at
        cleaned_data.merge!({:server => server_name })
      end

      subject       = "#{email_prefix}#{"[#{occurrences} SUMMARIZED]" if first_seen_at}#{cleaned_data[:error]}"[0,300]
      recipients    = exception_recipients
      from          = sender_address
      @cleaned_data = cleaned_data

      mail(:from    => from,
           :to      => recipients,
           :subject => subject)
    end

    def escalation_notification( summary, data)
      subject       = "#{email_environment} Escalation: #{summary}"
      from          = sender_address.gsub('xception', 'scalation')
      recipients    = escalation_recipients rescue exception_recipients

      @summary      = summary
      @server       = ExceptionHandling.server_name
      @cleaned_data = data

      mail(:from    => from,
           :to      => recipients,
           :subject => subject)
    end

    def log_parser_exception_notification( cleaned_data, key )
      if cleaned_data.is_a?(Hash)
        cleaned_data = cleaned_data.symbolize_keys
        local_subject = cleaned_data[:error]
      else
        local_subject = "#{key}: #{cleaned_data}"
        cleaned_data  = { :error => cleaned_data.to_s }
      end

      @subject       = "#{email_prefix}#{local_subject}"[0,300]
      @recipients    = exception_recipients
      from           = sender_address
      @cleaned_data  = cleaned_data

      mail(:from    => from,
           :to      => @recipients,
           :subject => @subject)
    end

    def self.mailer_method_category
      {
        :exception_notification            => :NetworkOptout,
        :log_parser_exception_notification => :NetworkOptout
      }
    end
  end
end