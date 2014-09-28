require 'timeout'
require 'active_support'
require 'active_support/core_ext/hash'

require 'invoca/utils'

require "exception_handling/mailer"
require "exception_handling/methods"
require "exception_handling/log_stub_error"
require "exception_handling/filter"
require "exception_handling/exception_filters"

_ = ActiveSupport::HashWithIndifferentAccess

module ExceptionHandling # never included

  class Warning < StandardError; end
  class MailerTimeout < Timeout::Error; end
  class ClientLoggingError < StandardError; end

  SUMMARY_THRESHOLD = 5
  SUMMARY_PERIOD = 60*60 # 1.hour

  SECTIONS = [:request, :session, :environment, :backtrace, :event_response]

  ENVIRONMENT_WHITELIST = [
/^HTTP_/,
/^QUERY_/,
/^REQUEST_/,
/^SERVER_/
  ]

  ENVIRONMENT_OMIT =(
<<EOF
CONTENT_TYPE: application/x-www-form-urlencoded
GATEWAY_INTERFACE: CGI/1.2
HTTP_ACCEPT: */*
HTTP_ACCEPT: */*, text/javascript, text/html, application/xml, text/xml, */*
HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
HTTP_ACCEPT_ENCODING: gzip, deflate
HTTP_ACCEPT_ENCODING: gzip,deflate
HTTP_ACCEPT_LANGUAGE: en-us
HTTP_CACHE_CONTROL: no-cache
HTTP_CONNECTION: Keep-Alive
HTTP_HOST: www.invoca.com
HTTP_MAX_FORWARDS: 10
HTTP_UA_CPU: x86
HTTP_VERSION: HTTP/1.1
HTTP_X_FORWARDED_HOST: www.invoca.com
HTTP_X_FORWARDED_SERVER: www2.invoca.com
HTTP_X_REQUESTED_WITH: XMLHttpRequest
LANG:
LANG:
PATH: /sbin:/usr/sbin:/bin:/usr/bin
PWD: /
RAILS_ENV: production
RAW_POST_DATA: id=500
REMOTE_ADDR: 10.251.34.225
SCRIPT_NAME: /
SERVER_NAME: www.invoca.com
SERVER_PORT: 80
SERVER_PROTOCOL: HTTP/1.1
SERVER_SOFTWARE: Mongrel 1.1.4
SHLVL: 1
TERM: linux
TERM: xterm-color
_: /usr/bin/mongrel_cluster_ctl
EOF
      ).split("\n")

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

    @filter_list_filename = "./config/exception_filters.yml"
    @mailer_send_enabled  = true
    @email_environment = ""
    @eventmachine_safe = false
    @eventmachine_synchrony = false

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
      exception_data = exception_to_data(exception, env, timestamp)

      if stub_handler
        return stub_handler.handle_stub_log_error(exception_data)
      end

      # TODO: add a more interesting custom description, like:
      # custom_description = ": caught and processed by Rack middleware filter #{rack_filter}"
      # which would be nice, but would also require changing quite a few tests
      custom_description = ""
      write_exception_to_log(exception, custom_description, timestamp)

      if should_send_email?
        controller = env['action_controller.instance']
        # controller may not exist in some cases (like most 404 errors)
        if controller
          extract_and_merge_controller_data(controller, exception_data)
          controller.session["last_exception_timestamp"] = ExceptionHandling.last_exception_timestamp
        end
        log_error_email(exception_data, exception)
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
    def log_error(exception_or_string, exception_context = '', controller = nil, treat_as_local = false)
      begin
        ex = make_exception(exception_or_string)
        timestamp = set_log_error_timestamp
        data = exception_to_data(ex, exception_context, timestamp)

        if stub_handler
          return stub_handler.handle_stub_log_error(data)
        end

        write_exception_to_log(ex, exception_context, timestamp)

        if treat_as_local
          return
        end

        if should_send_email?
          controller ||= current_controller

          if block_given?
            # the expectation is that if the caller passed a block then they will be
            # doing their own merge of hash values into data
            begin
              yield data
            rescue Exception => ex
              data.merge!(:environment => "Exception in yield: #{ex.class}:#{ex}")
            end
          elsif controller
          # most of the time though, this method will not get passed a block
          # and additional hash data is extracted from the controller
            extract_and_merge_controller_data(controller, data)
          end

          log_error_email(data, ex)
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
        ExceptionHandling.logger.fatal(
          if ActionView::TemplateError === ex
            "#{ex} Error:#{timestamp}"
          else
            "\n(Error:#{timestamp}) #{ex.class} #{exception_context} (#{ex.message}):\n  " + clean_backtrace(ex).join("\n  ") + "\n\n"
          end
        )
      end
    end

    #
    # Pull certain fields out of the controller and add to the data hash.
    #
    def extract_and_merge_controller_data(controller, data)
      data[:request] = {
        :params      => controller.request.parameters.to_hash,
        :rails_root  => defined?(Rails) ? Rails.root : "Rails.root not defined. Is this a test environment?",
        :url         => controller.complete_request_uri
      }
      data[:environment].merge!(controller.request.env.to_hash)

      controller.session[:fault_in_session]
      data[:session] = {
        :key         => controller.request.session_options[:id],
        :data        => controller.session.dup
      }
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
      escalate(email_subject, ex, ExceptionHandling.last_exception_timestamp)
    end

    def escalate_warning(message, email_subject)
      ex = Warning.new(message)
      log_error(ex)
      escalate(email_subject, ex, ExceptionHandling.last_exception_timestamp)
    end

    def ensure_escalation(email_subject)
      begin
        yield
      rescue => ex
        escalate_error(ex, email_subject)
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

    def enhance_exception_data(data)
      return if ! ExceptionHandling.custom_data_hook
      begin
        ExceptionHandling.custom_data_hook.call(data)
      rescue Exception => ex
        # can't call log_error here or we will blow the call stack
        log_info( "Unable to execute custom custom_data_hook callback. #{ex.message} #{ex.backtrace.each {|l| "#{l}\n"}}" )
      end
    end

    private

    def log_error_email( data, exc )
      enhance_exception_data( data )
      normalize_exception_data( data )
      clean_exception_data( data )

      SECTIONS.each { |section| add_to_s( data[section] ) if data[section].is_a? Hash }

      if exception_filters.filtered?( data )
        return
      end

      if summarize_exception( data ) != :Summarized
        deliver(ExceptionHandling::Mailer.exception_notification(data))
      end

      execute_custom_log_error_callback(data, exc)

      nil
    end

    def execute_custom_log_error_callback(exception_data, exception)
      return if ! ExceptionHandling.post_log_error_hook
      begin
        ExceptionHandling.post_log_error_hook.call(exception_data, exception)
      rescue Exception => ex
        # can't call log_error here or we will blow the call stack
        log_info( "Unable to execute custom log_error callback. #{ex.message} #{ex.backtrace.each {|l| "#{l}\n"}}" )
      end
    end

    def escalate( email_subject, ex, timestamp )
      data = exception_to_data( ex, nil, timestamp )
      deliver(ExceptionHandling::Mailer.escalation_notification(email_subject, data))
    end

    def deliver(mail_object)
      if ExceptionHandling.eventmachine_safe
        EventMachine.schedule do # in case we're running outside the reactor
          async_send_method = ExceptionHandling.eventmachine_synchrony ? :asend : :send
          smtp_settings = ActionMailer::Base.smtp_settings
          send_deferrable = EventMachine::Protocols::SmtpClient.__send__(
              async_send_method,
              {
                :host     => smtp_settings[:address],
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

    def clean_exception_data( data )
      if (as_array = data[:backtrace].to_a).size == 1
        data[:backtrace] = as_array.first.to_s.split(/\n\s*/)
      end

      if data[:request].is_a?(Hash) && data[:request][:params].is_a?(Hash)
        data[:request][:params] = clean_params(data[:request][:params])
      end

      if data[:environment].is_a?(Hash)
        data[:environment] = clean_environment(data[:environment])
      end
    end

    def normalize_exception_data( data )
      if data[:location].nil?
      data[:location] = {}
        if data[:request] && data[:request].key?( :params )
          data[:location][:controller] = data[:request][:params]['controller']
          data[:location][:action]     = data[:request][:params]['action']
        end
      end
      if data[:backtrace] && data[:backtrace].first
        first_line = data[:backtrace].first

        # template exceptions have the line number and filename as the first element in backtrace
        if matched = first_line.match( /on line #(\d*) of (.*)/i )
          backtrace_hash = {}
          backtrace_hash[:line] = matched[1]
          backtrace_hash[:file] = matched[2]
        else
          backtrace_hash = Hash[* [:file, :line].zip( first_line.split( ':' )[0..1]).flatten ]
        end

        data[:location].merge!( backtrace_hash )
      end
    end

    def clean_params params
      params.each do |k, v|
        params[k] = "[FILTERED]" if k =~ /password/
      end
    end

    def clean_environment env
      Hash[ env.map do |k, v|
        [k, v] if !"#{k}: #{v}".in?(ENVIRONMENT_OMIT) && ENVIRONMENT_WHITELIST.any? { |regex| k =~ regex }
      end.compact ]
    end

    def exception_filters
      @exception_filters ||= ExceptionFilters.new( ExceptionHandling.filter_list_filename )
    end

    def clean_backtrace(exception)
      if exception.backtrace.nil?
        ['<no backtrace>']
      elsif exception.is_a?(ClientLoggingError)
        exception.backtrace
      elsif defined?(Rails)
        Rails.backtrace_cleaner.clean(exception.backtrace)
      else
        exception.backtrace
      end
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
      $stderr.puts("ExceptionHandling.log_error_email rescued exception while logging #{exception_context}: #{exception_or_string}:\n#{ex.class}: #{ex}\n#{ex.backtrace.join("\n")}")
      log_error(ex, "ExceptionHandling::log_error_email rescued exception while logging #{exception_context}: #{exception_or_string}", nil, true)
    end

    def add_to_s( data_section )
      data_section[:to_s] = dump_hash( data_section )
    end

    def exception_to_data( exception, exception_context, timestamp )
      data = ActiveSupport::HashWithIndifferentAccess.new
      data[:error_class] = exception.class.name
      data[:error_string]= "#{data[:error_class]}: #{exception.message}"
      data[:timestamp]   = timestamp
      data[:backtrace]   = clean_backtrace(exception)
      if exception_context && exception_context.is_a?(Hash)
        # if we are a hash, then we got called from the DebugExceptions rack middleware filter
        # and we need to do some things different to get the info we want
        data[:error] = "#{data[:error_class]}: #{exception.message}"
        data[:session] = exception_context['rack.session']
        data[:environment] = exception_context
      else
        data[:error]       = "#{data[:error_string]}#{': ' + exception_context.to_s unless exception_context.blank?}"
        data[:environment] = { :message => exception_context }
      end
      data
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

    def dump_hash( h, indent_level = 0 )
      result = ""
      h.sort { |a, b| a.to_s <=> b.to_s }.each do |key, value|
        result << ' ' * (2 * indent_level)
        result << "#{key}:"
        case value
        when Hash
          result << "\n" << dump_hash( value, indent_level + 1 )
        else
          result << " #{value}\n"
        end
      end unless h.nil?
      result
    end
  end
end
