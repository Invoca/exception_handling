require 'timeout'
require 'active_support'
require 'active_support/core_ext/hash'

require 'invoca/utils'

require "exception_handling/mailer"
require "exception_handling/sensu"
require "exception_handling/methods"
require "exception_handling/log_stub_error"
require "exception_handling/exception_description"
require "exception_handling/exception_catalog"
require "exception_handling/exception_info"

_ = ActiveSupport::HashWithIndifferentAccess

module ExceptionHandling # never included

  class Warning < StandardError; end
  class MailerTimeout < Timeout::Error; end
  class ClientLoggingError < StandardError; end

  SUMMARY_THRESHOLD = 5
  SUMMARY_PERIOD = 60*60 # 1.hour

  AUTHENTICATION_HEADERS = ['HTTP_AUTHORIZATION','X-HTTP_AUTHORIZATION','X_HTTP_AUTHORIZATION','REDIRECT_X_HTTP_AUTHORIZATION']

  class << self

    #
    # required settings
    #
    attr_accessor :server_name
    attr_accessor :sender_address
    attr_accessor :exception_recipients
    attr_accessor :logger

    def server_name
      @server_name or raise ArgumentError, "You must assign a value to #{self.name}.server_name"
    end

    def sender_address
      @sender_address or raise ArgumentError, "You must assign a value to #{self.name}.sender_address"
    end

    def exception_recipients
      @exception_recipients or raise ArgumentError, "You must assign a value to #{self.name}.exception_recipients"
    end

    def logger
      @logger or raise ArgumentError, "You must assign a value to #{self.name}.logger"
    end

    #
    # optional settings
    #
    attr_accessor :escalation_recipients
    attr_accessor :email_environment
    attr_accessor :filter_list_filename
    attr_accessor :mailer_send_enabled
    attr_accessor :eventmachine_safe
    attr_accessor :eventmachine_synchrony
    attr_accessor :custom_data_hook
    attr_accessor :post_log_error_hook
    attr_accessor :stub_handler
    attr_accessor :sensu_host
    attr_accessor :sensu_port
    attr_accessor :sensu_prefix

    @filter_list_filename = "./config/exception_filters.yml"
    @mailer_send_enabled  = true
    @email_environment = ""
    @eventmachine_safe = false
    @eventmachine_synchrony = false
    @sensu_host = "127.0.0.1"
    @sensu_port = 3030
    @sensu_prefix = ""

    # set this for operation within an eventmachine reactor
    def eventmachine_safe=(bool)
      if bool != true && bool != false
        raise ArgumentError, "#{self.name}.eventmachine_safe must be a boolean."
      end
      if bool
        require 'eventmachine'
        require 'em/protocols/smtpclient'
      end
      @eventmachine_safe = bool
    end

    # set this for EM::Synchrony async operation
    def eventmachine_synchrony=(bool)
      if bool != true && bool != false
        raise ArgumentError, "#{self.name}.eventmachine_synchrony must be a boolean."
      end
      @eventmachine_synchrony = bool
    end

    #
    # internal settings (don't set directly)
    #
    attr_accessor :current_controller
    attr_accessor :last_exception_timestamp
    attr_accessor :periodic_exception_intervals

    #
    # Gets called by Rack Middleware: DebugExceptions or ShowExceptions
    # it does 2 things:
    #   log the error
    #   email the error
    #
    # but not during functional tests, when rack middleware is not used
    #
    def log_error_rack(exception, env, rack_filter)
      timestamp = set_log_error_timestamp
      exception_info = ExceptionInfo.new(exception, env, timestamp)

      if stub_handler
        return stub_handler.handle_stub_log_error(exception_info.data)
      end

      # TODO: add a more interesting custom description, like:
      # custom_description = ": caught and processed by Rack middleware filter #{rack_filter}"
      # which would be nice, but would also require changing quite a few tests
      custom_description = ""
      write_exception_to_log(exception, custom_description, timestamp)

      if honeybadger?
        send_exception_to_honeybadger(exception_info)
      end

      if should_send_email?
        # controller may not exist in some cases (like most 404 errors)
        if (controller = exception_info.controller)
          controller.session["last_exception_timestamp"] = last_exception_timestamp
        end
        log_error_email(exception_info)
      end
    end

    #
    # Normal Operation:
    #   Called directly by our code, usually from rescue blocks.
    #   Does two things: write to log file and send an email
    #
    # Functional Test Operation:
    #   Calls into handle_stub_log_error and returns. no log file. no email.
    #
    def log_error(exception_or_string, exception_context = '', controller = nil, treat_as_local = false, &data_callback)
      begin
        ex = make_exception(exception_or_string)
        timestamp = set_log_error_timestamp
        exception_info = ExceptionInfo.new(ex, exception_context, timestamp, controller || current_controller, data_callback)

        if stub_handler
          return stub_handler.handle_stub_log_error(exception_info.data)
        end

        write_exception_to_log(ex, exception_context, timestamp)

        if honeybadger?
          send_exception_to_honeybadger(exception_info)
        end

        if treat_as_local
          return
        end

        if should_send_email?
          log_error_email(exception_info)
        end

      rescue LogErrorStub::UnexpectedExceptionLogged, LogErrorStub::ExpectedExceptionNotLogged
        raise
      rescue Exception => ex
        $stderr.puts("ExceptionHandling.log_error rescued exception while logging #{exception_context}: #{exception_or_string}:\n#{ex.class}: #{ex}\n#{ex.backtrace.join("\n")}")
        write_exception_to_log(ex, "ExceptionHandling.log_error rescued exception while logging #{exception_context}: #{exception_or_string}", timestamp)
      end
    end

    #
    # Write an exception out to the log file using our own custom format.
    #
    def write_exception_to_log(ex, exception_context, timestamp)
      ActiveSupport::Deprecation.silence do
        ExceptionHandling.logger.fatal("\n(Error:#{timestamp}) #{ex.class} #{exception_context} (#{encode_utf8(ex.message.to_s)}):\n  " + clean_backtrace(ex).join("\n  ") + "\n\n")
      end
    end

    #
    # Log exception to honeybadger.io.
    #
    def send_exception_to_honeybadger(exception_info)
      ex = exception_info.exception
      exception_description = exception_info.exception_description
      unless exception_info.send_to_honeybadger?
        log_info("Filtered exception using '#{exception_description.filter_name}'; not sending notification to Honeybadger")
        return
      end

      Honeybadger.notify(error_class:   exception_description ? exception_description.filter_name : ex.class.name,
                         error_message: ex.message.to_s,
                         exception:     ex,
                         context:       exception_info.honeybadger_context_data)
    end

    #
    # Check if Honeybadger defined.
    #
    def honeybadger?
      Object.const_defined?("Honeybadger")
    end

    def log_warning( message )
      log_error( Warning.new(message) )
    end

    def log_info( message )
      ExceptionHandling.logger.info( message )
    end

    def log_debug( message )
      ExceptionHandling.logger.debug( message )
    end

    def ensure_safe( exception_context = "" )
      yield
    rescue => ex
      log_error ex, exception_context
      return nil
    end

    def ensure_completely_safe( exception_context = "" )
      yield
    rescue SystemExit, SystemStackError, NoMemoryError, SecurityError, SignalException
      raise
    rescue Exception => ex
      log_error ex, exception_context
    end

    def escalate_error(exception_or_string, email_subject)
      ex = make_exception(exception_or_string)
      log_error(ex)
      escalate(email_subject, ex, last_exception_timestamp)
    end

    def escalate_warning(message, email_subject)
      ex = Warning.new(message)
      log_error(ex)
      escalate(email_subject, ex, last_exception_timestamp)
    end

    def ensure_escalation(email_subject)
      begin
        yield
      rescue => ex
        escalate_error(ex, email_subject)
        nil
      end
    end

    def alert_warning(exception_or_string, alert_name, exception_context)
      ex = make_exception(exception_or_string)
      log_error(ex, exception_context)
      begin
        ExceptionHandling::Sensu.generate_event(alert_name, exception_context.to_s + "\n" + encode_utf8(ex.message.to_s))
      rescue => send_ex
        log_error(send_ex, 'ExceptionHandling.alert_warning')
      end
    end

    def ensure_alert(alert_name, exception_context)
      begin
        yield
      rescue => ex
        alert_warning(ex, alert_name, exception_context)
        nil
      end
    end

    def set_log_error_timestamp
      ExceptionHandling.last_exception_timestamp = Time.now.to_i
    end

    def should_send_email?
      ExceptionHandling.mailer_send_enabled
    end

    def trace_timing(description)
      result = nil
      time = Benchmark.measure do
        result = yield
      end
      log_info "#{description} %.4fs  " % time.real
      result
    end

    def log_periodically(exception_key, interval, message)
      self.periodic_exception_intervals ||= {}
      last_logged = self.periodic_exception_intervals[exception_key]
      if !last_logged || ( (last_logged + interval) < Time.now )
        log_error( message )
        self.periodic_exception_intervals[exception_key] = Time.now
      end
    end

    def encode_utf8(string)
      string.encode('UTF-8',
                    replace: '?',
                    undef:   :replace,
                    invalid: :replace)
    end

    def clean_backtrace(exception)
      backtrace = if exception.backtrace.nil?
        ['<no backtrace>']
      elsif exception.is_a?(ClientLoggingError)
        exception.backtrace
      elsif defined?(Rails)
        Rails.backtrace_cleaner.clean(exception.backtrace)
      else
        exception.backtrace
      end

      # The rails backtrace cleaner returns an empty array for a backtrace if the exception was raised outside the app (inside a gem for instance)
      if backtrace.is_a?(Array) && backtrace.empty?
        exception.backtrace
      else
        backtrace
      end
    end

    private

    def log_error_email(exception_info)
      data = exception_info.enhanced_data
      exception_description = exception_info.exception_description

      if exception_description && !exception_description.send_email
        ExceptionHandling.logger.warn( "Filtered exception using '#{exception_description.filter_name}'; not sending email to notify" )
      else
        if summarize_exception(data) != :Summarized
          deliver(ExceptionHandling::Mailer.exception_notification(data))
        end
      end

      execute_custom_log_error_callback(data, exception_info.exception)
      nil
    end

    def execute_custom_log_error_callback(exception_data, exception)
      return if ! ExceptionHandling.post_log_error_hook
      begin
        ExceptionHandling.post_log_error_hook.call(exception_data, exception)
      rescue Exception => ex
        # can't call log_error here or we will blow the call stack
        log_info( "Unable to execute custom log_error callback. #{encode_utf8(ex.message.to_s)} #{ex.backtrace.each {|l| "#{l}\n"}}" )
      end
    end

    def escalate( email_subject, ex, timestamp )
      exception_info = ExceptionInfo.new(ex, nil, timestamp)
      deliver(ExceptionHandling::Mailer.escalation_notification(email_subject, exception_info.data))
    end

    def deliver(mail_object)
      if ExceptionHandling.eventmachine_safe
        EventMachine.schedule do # in case we're running outside the reactor
          async_send_method = ExceptionHandling.eventmachine_synchrony ? :asend : :send
          smtp_settings = ActionMailer::Base.smtp_settings
          dns_deferrable = EventMachine::DNS::Resolver.resolve(smtp_settings[:address])
          dns_deferrable.callback do |addrs|
            send_deferrable = EventMachine::Protocols::SmtpClient.__send__(
                async_send_method,
                {
                  :host     => addrs.first,
                  :port     => smtp_settings[:port],
                  :domain   => smtp_settings[:domain],
                  :auth     => {:type=>:plain, :username=>smtp_settings[:user_name], :password=>smtp_settings[:password]},
                  :from     => mail_object['from'].to_s,
                  :to       => mail_object['to'].to_s,
                  :content     => "#{mail_object}\r\n.\r\n"
                }
            )
            send_deferrable.errback { |err| ExceptionHandling.logger.fatal("Failed to email by SMTP: #{err.inspect}") }
          end
          dns_deferrable.errback  { |err| ExceptionHandling.logger.fatal("Failed to resolv DNS for #{smtp_settings[:address]}: #{err.inspect}") }
        end
      else
        safe_email_deliver do
          mail_object.deliver
        end
      end
    end

    def safe_email_deliver
      Timeout::timeout 30, MailerTimeout do
        yield
      end
    rescue StandardError, MailerTimeout => ex
      #$stderr.puts("ExceptionHandling::safe_email_deliver rescued: #{ex.class}: #{ex}\n#{ex.backtrace.join("\n")}")
      log_error( ex, "ExceptionHandling::safe_email_deliver", nil, true )
    end

    def clear_exception_summary
      @last_exception = nil
    end

    # Returns :Summarized iff exception has been added to summary and therefore should not be sent.
    def summarize_exception( data )
      if @last_exception
        same_signature = @last_exception[:backtrace] == data[:backtrace]

        case @last_exception[:state]

        when :NotSummarized
          if same_signature
            @last_exception[:count] += 1
            if @last_exception[:count] >= SUMMARY_THRESHOLD
              @last_exception.merge! :state => :Summarized, :first_seen => Time.now, :count => 0
            end
            return nil
          end

        when :Summarized
          if same_signature
            @last_exception[:count] += 1
            if Time.now - @last_exception[:first_seen] > SUMMARY_PERIOD
              send_exception_summary(data, @last_exception[:first_seen], @last_exception[:count])
              @last_exception.merge! :first_seen => Time.now, :count => 0
            end
            return :Summarized
          elsif @last_exception[:count] > 0 # send the left-over, if any
            send_exception_summary(@last_exception[:data], @last_exception[:first_seen], @last_exception[:count])
          end

        else
          raise "Unknown state #{@last_exception[:state]}"
        end
      end

      # New signature we haven't seen before.  Not summarized yet--we're just starting the count.
      @last_exception = {
        :data       => data,
        :count      => 1,
        :first_seen => Time.now,
        :backtrace  => data[:backtrace],
        :state      => :NotSummarized
      }
      nil
    end

    def send_exception_summary( exception_data, first_seen, occurrences )
      Timeout::timeout 30, MailerTimeout do
        deliver(ExceptionHandling::Mailer.exception_notification(exception_data, first_seen, occurrences))
      end
    rescue StandardError, MailerTimeout => ex
      original_error = exception_data[:error_string]
      log_prefix = "ExceptionHandling.log_error_email rescued exception while logging #{original_error}"
      $stderr.puts("#{log_prefix}:\n#{ex.class}: #{ex}\n#{ex.backtrace.join("\n")}")
      log_info(log_prefix)
    end

    def make_exception(exception_or_string)
      if exception_or_string.is_a?(Exception)
        exception_or_string
      else
        begin
          # raise to capture a backtrace
          raise StandardError, exception_or_string
        rescue => ex
          ex
        end
      end
    end
  end
end
