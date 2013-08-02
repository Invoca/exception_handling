require 'timeout'

if defined?(EVENTMACHINE_EXCEPTION_HANDLING) && EVENTMACHINE_EXCEPTION_HANDLING
  require 'em/protocols/smtpclient'
end

module ExceptionHandling # never included

  class Warning < StandardError; end
  class MailerTimeout < Timeout::Error; end

  SUMMARY_THRESHOLD = 5
  SUMMARY_PERIOD = 1.hour


  SECTIONS = [:request, :session, :environment, :backtrace, :event_response]
  EXCEPTION_FILTER_LIST_PATH = "#{RAILS_ROOT}/config/exception_filters.yml"

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
HTTP_HOST: www.ringrevenue.com
HTTP_MAX_FORWARDS: 10
HTTP_UA_CPU: x86
HTTP_VERSION: HTTP/1.1
HTTP_X_FORWARDED_HOST: www.ringrevenue.com
HTTP_X_FORWARDED_SERVER: www2.ringrevenue.com
HTTP_X_REQUESTED_WITH: XMLHttpRequest
LANG:
LANG:
PATH: /sbin:/usr/sbin:/bin:/usr/bin
PWD: /
RAILS_ENV: production
RAW_POST_DATA: id=500
REMOTE_ADDR: 10.251.34.225
SCRIPT_NAME: /
SERVER_NAME: www.ringrevenue.com
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
    attr_accessor :current_controller
    attr_accessor :last_exception_timestamp
    attr_accessor :periodic_exception_intervals

    attr_accessor :stub_handler # See log_error_stub.rb. Used in tests

    def log_error(exception_or_string, exception_context = '', controller = nil)
      if stub_handler # See log_error_stub.rb. Used for tests
        return stub_handler.handle_stub_log_error(exception_or_string, exception_context, controller)
      end

      begin
        ex = make_exception( exception_or_string )

        timestamp = log_error_local( ex, exception_context )

        if should_send_email?
          controller ||= current_controller
          data = exception_to_data( ex, exception_context, timestamp )
          if block_given?
            begin
              yield data
            rescue Exception => ex
              data.merge!(:environment => "Exception in yield: #{ex.class}:#{ex}")
            end
          elsif controller
            data[:request] = {
              :params      => controller.request.parameters.to_hash,
              :rails_root  => File.expand_path(RAILS_ROOT),
              :url         => "#{controller.request.protocol}#{controller.request.host}#{controller.request.request_uri}"
            }
            data[:environment].merge!(controller.request.env.to_hash)

            controller.session[:fault_in_session]
            data[:session] = {
              :key         => controller.request.session_options[:id],
              :data        => controller.session.dup
            }
          end
          log_error_email( data, ex )
        end
      rescue Exception => ex
        log_error_local(ex, "ExceptionHandling.log_error rescued exception while logging #{exception_context}: #{exception_or_string}")
      end
    end

    def log_warning( message )
      log_error( Warning.new(message) )
    end

    def log_info( message )
      RAILS_DEFAULT_LOGGER.info( message )
    end

    def log_debug( message )
      RAILS_DEFAULT_LOGGER.debug( message )
    end

    def ensure_safe( exception_context = "" )
      begin
        yield
      rescue => ex
        log_error ex, exception_context
        return nil
      end
    end

    def ensure_escalation( email_subject )
      begin
        yield
      rescue => ex
        log_error ex
        escalate(email_subject, ex, ExceptionHandling.last_exception_timestamp)
        return nil
      end
    end

    def log_error_local( exception, exception_context )
      # Duplicates code from ActionController::Rescue, but the code
      # is in the rails library and it is protected.
      timestamp = Time.now.to_i
      ActiveSupport::Deprecation.silence do
        ExceptionHandling.last_exception_timestamp = timestamp
        Rails.logger.fatal(
          if ActionView::TemplateError === exception
            "#{exception.to_s} Error:#{timestamp}"
          else
            "\n(Error:#{timestamp}) #{exception.class} #{exception_context} (#{exception.message}):\n  " +
            clean_backtrace(exception.backtrace).join("\n  ") + "\n\n"
          end
        )
      end
      timestamp
    end

    def should_send_email?
      defined?( EXCEPTION_HANDLING_MAILER_SEND_MAIL ) && EXCEPTION_HANDLING_MAILER_SEND_MAIL
    end

    def trace_timing description
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

    private

    def log_error_email( data, exc )
      enhance_exception_data( data )

      clean_exception_data( data )

      SECTIONS.each { |section| add_to_s( data[section] ) if data[section].is_a?(Hash) }

      if exception_filters.filtered?( data )
        return
      end

      if summarize_exception( data ) == :Summarized
        return
      end

      deliver(ExceptionHandlingMailer.send(:new, 'exception_notification', data))

      Errplane.transmit(exc, :custom_data => data)
      nil
    end

    def escalate( email_subject, ex, timestamp )
      data = exception_to_data( ex, nil, timestamp )
      deliver(ExceptionHandlingMailer.send(:new, 'escalation_notification', email_subject, data))
    end

    def deliver(mail_object)
      mail_message = mail_object.mail
      if defined?(EVENTMACHINE_EXCEPTION_HANDLING) && EVENTMACHINE_EXCEPTION_HANDLING
        EventMachine.schedule do # in case we're running outside the reactor
          async_send_method = EVENTMACHINE_EXCEPTION_HANDLING == :Synchrony ? :asend : :send
          smtp_settings = ActionMailer::Base.smtp_settings
          send_deferrable = EventMachine::Protocols::SmtpClient.__send__(
              async_send_method,
              {
                :host     => smtp_settings[:address],
                :port     => smtp_settings[:port],
                :domain   => smtp_settings[:domain],
                :auth     => {:type=>:plain, :username=>smtp_settings[:user_name], :password=>smtp_settings[:password]},
                :from     => mail_message['from'],
                :to       => mail_message['to'],
                :content  => "#{mail_message}\r\n.\r\n"
              }
          )
          send_deferrable.errback { |err| Rails.logger.fatal("Failed to email by SMTP: #{err.inspect}") }
        end
      else
        safe_email_deliver do
          mail_object.deliver!
        end
      end
    end

    def safe_email_deliver
      Timeout::timeout 30, MailerTimeout do
        yield
      end
    rescue StandardError, MailerTimeout => ex
      log_error_local( ex, "ExceptionHandling::safe_email_deliver" )
    end

    def clean_exception_data( data )
      normalize_exception_data( data )
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
      data[:location] = {}
      if data[:request]._?.key?( :params )
        data[:location][:controller] = data[:request][:params]['controller']
        data[:location][:action]     = data[:request][:params]['action']
      end
      if data[:backtrace]._?.first
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
      env.select_hash do |k, v|
        ! ( "#{k}: #{v}".in? ENVIRONMENT_OMIT ) && ENVIRONMENT_WHITELIST.any? { |regex| k =~ regex }
      end
    end

    def exception_filters
      @exception_filters ||= ExceptionFilters.new( EXCEPTION_FILTER_LIST_PATH )
    end

    def clean_backtrace( backtrace )
      return ['<no backtrace>'] unless backtrace
      Rails.backtrace_cleaner.clean( backtrace )
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

    def send_exception_summary(exception_data, first_seen, occurrences)
      deliver(ExceptionHandlingMailer.send(:new, 'exception_notification', exception_data, first_seen, occurrences))
    end

  public # TODO: fix test to not use this.
    def enhance_exception_data(data)
      # If we get a routing error without an HTTP referrer, assume we have one of them hackers poking at us.
      if data[:request]._?[:params]._?[:controller] != 'vxml'
        if data[:error_class].in? ['ActionController::RoutingError', 'ActionController::UnknownAction', 'ActiveRecord::RecordNotFound']
          if data[:environment]['HTTP_HOST']
            if data[:environment]['HTTP_REFERER'].blank?
              data[:error] = "ScriptKiddie suspected because of HTTP request without a referer. Original exception: #{data[:error]}"
              data[:error_class] = 'ScriptKiddie'
            elsif data[:session] && data[:session][:data] && data[:session][:data][:user_id]
              if data[:environment]['HTTP_REFERER'] =~/\/session\/|\/login/
                data[:error] = "Found broken link after user logged in from #{data[:environment]['HTTP_REFERER']}. Original exception: #{data[:error]}"
                data[:error_class] = 'BrokenLinkAfterLogin'
              else
                data[:error] = "Logged in user experienced broken link on page #{data[:environment]['HTTP_REFERER']}. Original exception: #{data[:error]}"
                data[:error_class] = 'BrokenLinkForUser'
              end
            elsif data[:environment]['HTTP_REFERER'] =~ /ringrevenue/
              data[:error] = "Broken link clicked on from local page #{data[:environment]['HTTP_REFERER']}. Original exception: #{data[:error]}"
              data[:error_class] = 'BrokenLocalLink'
            else
              data[:error] = "Broken link clicked on from remote page #{data[:environment]['HTTP_REFERER']}. Original exception: #{data[:error]}"
              data[:error_class] = 'BrokenRemoteLink'
            end
          end
        end
      end

      # Provide details on session data.
      begin
        if data[:session] && data[:session][:data]

          data[:user_details] = {}

          if data[:session][:data][:impersonated_organization_pk]
            data[:user_details][:impersonated_organization] = ApplicationModel.from_pk(data[:session][:data][:impersonated_organization_pk],
                                                                                       { :allowed_types => [Advertiser,Affiliate,Network] } ) rescue nil
          end

          data[:session][:data].each do |key, value|
            id_match = /^(.*)_id$/.match( key.to_s )
            if id_match && value.is_a?( Numeric )
              id_details = ( obj = Object.const_get(id_match[1].camelize).find(value) ).to_s rescue "not found"
              case obj
              when User
                data[:user_details][:user]     = obj
                data[:user_details][:username] = obj.username
              when OrganizationMembership
                data[:user_details][:organization] = obj.organization
              end
              data[:session][:data][key] = "#{value} - #{id_details}"
            end
          end

          # Handle basic authentication
          if credentials = AUTHENTICATION_HEADERS.map_and_find{ |header| data[:environment][header] }
            username = ActiveSupport::Base64.decode64(credentials.split(' ', 2).last).split(/:/).first

            if !data[:user_details][:username] && username.nonblank?
              data[:user_details][:username] = Username.find_by_username(username)
              data[:user_details][:user] = data[:user_details][:username]._?.user
            end
          end

          # fill in organization if still not set
          if data[:user_details][:user] && !data[:user_details][:organization]
            data[:user_details][:organization] = data[:user_details][:user].default_organization
          end

          # do not show authentication headers
          AUTHENTICATION_HEADERS.each{ |header| data[:environment].delete(header) }
        end
      rescue Exception => ex
        log_error_local(ex, 'Data mapping aborted because of exception')
        data[:session][:data]['exceptionnote'] = "data mapping aborted because of exception.  Mapping exception is in server log."
      end
    end

  private
    def add_to_s( data_section )
      data_section[:to_s] = dump_hash( data_section )
    end

    def exception_to_data( exception, exception_context, timestamp )
      data = HashWithIndifferentAccess.new
      data[:error_class] = exception.class.name
      data[:error_string]= "#{data[:error_class]}: #{exception.message}"
      data[:error]       = "#{data[:error_string]}#{': ' + exception_context unless exception_context.blank?}"
      data[:backtrace]   = clean_backtrace(exception.backtrace)
      data[:environment] = ENV.to_hash
      data[:timestamp]   = timestamp
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

  class ExceptionFilters
    class Filter
      def initialize filter_name, regexes
        @regexes = regexes.map_hash do |section, regex|
          section = section.to_sym
          raise "Unknown section: #{section}" unless section == :error || section.in?( ExceptionHandling::SECTIONS )
          Regexp.new( regex, 'i' ) unless regex.blank?
        end

        raise "Filter #{filter_name} has all blank regexes" if @regexes.all? { |section, regex| regex.nil? }
      end

      def match?(exception_data)
        @regexes.all? do |section, regex|
          regex.nil? ||
            case exception_data[section]
            when String
              regex =~ exception_data[section]
            when Array
              exception_data[section].any? { |row| row =~ regex }
            when Hash
              exception_data[section] && exception_data[section][:to_s] =~ regex
            when NilClass
              false
            else
              raise "Unexpected class #{exception_data[section].class.name}"
            end
        end
      end
    end

    def initialize( filter_path )
      @filter_path = filter_path
      @filters = { }
      @filters_last_modified_time = nil
    end

    def filtered?( exception_data )
      refresh_filters

      @filters.any? do |name, filter|
        if ( match = filter.match?( exception_data ) )
          RAILS_DEFAULT_LOGGER.warn( "Filtered exception using '#{name}'; not sending email to notify" )
        end
        match
      end
    end

    private

    def refresh_filters
      mtime = last_modified_time
      if @filters_last_modified_time.nil? || mtime != @filters_last_modified_time
        RAILS_DEFAULT_LOGGER.info( "Reloading filter list from: #{@filter_path}.  Last loaded time: #{@filters_last_modified_time}. Last modified time: #{mtime}" )
        @filters_last_modified_time = mtime # make race condition fall on the side of reloading unnecessarily next time rather than missing a set of changes

        @filters = load_file
      end

    rescue => ex # any exceptions
      ExceptionHandling::log_error_local( ex, "ExceptionRegexes::refresh_filters: #{@filter_path}" )
    end

    def load_file
      # store all strings from YAML file into regex's on initial load, instead of converting to regex on every exception that is logged
      filters = YAML::load_file( @filter_path )
      filters.map_hash do |filter_name, regexes|
        Filter.new( filter_name, regexes )
      end
    end

    def last_modified_time
      File.mtime( @filter_path )
    end
  end


public

  module Methods # included on models and controllers
    protected
    def log_error( exception_or_string, exception_context = '' )
      controller = self if respond_to?( :request ) && respond_to?( :session )
      ExceptionHandling.log_error( exception_or_string, exception_context, controller )
    end

    def log_warning( message )
      log_error( Warning.new(message) )
    end

    def log_info( message )
      RAILS_DEFAULT_LOGGER.info( message )
    end

    def log_debug( message )
      RAILS_DEFAULT_LOGGER.debug( message )
    end

    def ensure_safe( exception_context = "" )
      begin
        yield
      rescue => ex
        log_error ex, exception_context
        nil
      end
    end

    def ensure_escalation(*args)
      ExceptionHandling.ensure_escalation(*args) do
        yield
      end
    end

    # Store aside the current controller when included
    LONG_REQUEST_SECONDS = (Rails.env == 'test' ? 300 : 30)
    def set_current_controller
      ExceptionHandling.current_controller = self
      result = nil
      time = Benchmark.measure do
        result = yield
      end
      name = " in #{controller_name}::#{action_name}" rescue " "
      log_error( "Long controller action detected#{name} %.4fs  " % time.real ) if time.real > LONG_REQUEST_SECONDS && !['development', 'test'].include?(Rails.env)
      result
    ensure
      ExceptionHandling.current_controller = nil
    end

    def self.included( controller )
      controller.around_filter :set_current_controller if controller.respond_to? :around_filter
    end
  end
end
