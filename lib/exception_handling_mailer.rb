class ExceptionHandling::Mailer < ActionMailer::Base
  default :content_type => "text/html"

  self.append_view_path "views"

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

  private

# Overrides the smtp deliverer for this mailer to use kerio.
#  def perform_delivery_smtp(mail = self.mail)
#    smtp_settings = {
#    :address              => "mail101.itekmail.com",
#    :port                 => "25",
#    :user_name            => "outbound@ringrevenue.com",
#    :password             => "sendmymail!",
#    :domain               => "www.ringrevenue.com",
#    :authentication       => :plain,
#    :enable_starttls_auto => true,
#    # These are used by action_mailer_optional_tls plugin
#    # and should be removed in favor of enable_starttls_auto
#    # when ruby version on production >= 1.8.6
#    :tls                  => true,
#    :ssl                  => true
#  }
#
#    mail = self.mail
#    destinations = mail.destinations
#    mail.ready_to_send
#    sender = (mail['return-path'] && mail['return-path'].spec) || mail['from']
#    sender = EmailAddress.new(sender).address
#
#    # This block should be used when ruby version >= 1.8.6
##    smtp = Net::SMTP.new(smtp_settings[:address], smtp_settings[:port])
##    # Uncomment to get debug output on stdout
##    # smtp.set_debug_output $stdout
##    smtp.enable_starttls_auto if smtp_settings[:enable_starttls_auto] && smtp.respond_to?(:enable_starttls_auto)
##    smtp.start(smtp_settings[:domain], smtp_settings[:user_name], smtp_settings[:password],
##               smtp_settings[:authentication]) do |smtp|
##      smtp.sendmail(mail.encoded, sender, destinations)
##    end
#
#    # This block is used with action_mailer_optional_tls plugin and ruby version < 1.8.6
#    Net::SMTP.start(smtp_settings[:address], smtp_settings[:port], smtp_settings[:domain],
#        smtp_settings[:user_name], smtp_settings[:password], smtp_settings[:authentication],
#        smtp_settings[:tls], smtp_settings[:ssl]) do |smtp|
#      smtp.sendmail(mail.encoded, mail.from, destinations)
#    end
#  end
end
