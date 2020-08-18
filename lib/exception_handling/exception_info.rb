# frozen_string_literal: true

module ExceptionHandling
  class ExceptionInfo

    ENVIRONMENT_ALLOWLIST = [
      /^HTTP_/,
      /^QUERY_/,
      /^REQUEST_/,
      /^SERVER_/
    ].freeze

    ENVIRONMENT_OMIT = <<~EOS.split("\n")
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
    EOS

    SECTIONS = [:request, :session, :environment, :backtrace, :event_response].freeze
    HONEYBADGER_CONTEXT_SECTIONS = [:timestamp, :error_class, :exception_context, :server, :scm_revision, :notes,
                                    :user_details, :request, :session, :environment, :backtrace, :event_response, :log_context].freeze

    attr_reader :exception, :controller, :exception_context, :timestamp

    def initialize(exception, exception_context, timestamp, controller: nil, data_callback: nil, log_context: nil)
      @exception = exception
      @exception_context = exception_context
      @timestamp = timestamp
      @controller = controller || controller_from_context(exception_context)
      @data_callback = data_callback
      @log_context = log_context
    end

    def data
      @data ||= exception_to_data
    end

    def enhanced_data
      @enhanced_data ||= exception_to_enhanced_data
    end

    def exception_description
      @exception_description ||= ExceptionHandling.exception_catalog.find(enhanced_data)
    end

    def send_to_honeybadger?
      ExceptionHandling.honeybadger_defined? && (!exception_description || exception_description.send_to_honeybadger)
    end

    def honeybadger_context_data
      @honeybadger_context_data ||= enhanced_data_to_honeybadger_context
    end

    def controller_name
      @controller_name ||= if @controller
                             @controller.request.parameters.with_indifferent_access[:controller]
                           end.to_s
    end

    private

    def controller_from_context(exception_context)
      exception_context.is_a?(Hash) ? exception_context["action_controller.instance"] : nil
    end

    def exception_to_data
      exception_message = @exception.message.to_s
      data = ActiveSupport::HashWithIndifferentAccess.new
      data[:error_class] = @exception.class.name
      data[:error_string] = "#{data[:error_class]}: #{ExceptionHandling.encode_utf8(exception_message)}"
      data[:timestamp]   = @timestamp
      data[:backtrace]   = ExceptionHandling.clean_backtrace(@exception)
      if @exception_context&.is_a?(Hash)
        # if we are a hash, then we got called from the DebugExceptions rack middleware filter
        # and we need to do some things different to get the info we want
        data[:error] = "#{data[:error_class]}: #{ExceptionHandling.encode_utf8(exception_message)}"
        data[:session] = @exception_context['rack.session']
        data[:environment] = @exception_context
      else
        data[:error]       = "#{data[:error_string]}#{': ' + @exception_context.to_s unless @exception_context.blank?}"
        data[:environment] = { message: @exception_context }
      end
      data
    end

    def exception_to_enhanced_data
      enhanced_data = exception_to_data
      extract_and_merge_controller_data(enhanced_data)
      customize_from_data_callback(enhanced_data)
      enhance_exception_data(enhanced_data)
      normalize_exception_data(enhanced_data)
      clean_exception_data(enhanced_data)
      stringify_sections(enhanced_data)

      description = ExceptionHandling.exception_catalog.find(enhanced_data)
      description ? ActiveSupport::HashWithIndifferentAccess.new(description.exception_data.merge(enhanced_data)) : enhanced_data
    end

    def enhance_exception_data(data)
      return if !ExceptionHandling.custom_data_hook

      begin
        ExceptionHandling.custom_data_hook.call(data)
      rescue Exception => ex
        # can't call log_error here or we will blow the call stack
        traces = ex.backtrace.join("\n")
        ExceptionHandling.log_info("Unable to execute custom custom_data_hook callback. #{ExceptionHandling.encode_utf8(ex.message.to_s)} #{traces}\n")
      end
    end

    def normalize_exception_data(data)
      if data[:location].nil?
        data[:location] = {}
        if data[:request]&.key?(:params)
          data[:location][:controller] = data[:request][:params]['controller']
          data[:location][:action]     = data[:request][:params]['action']
        end
      end
      if data[:backtrace]&.first
        first_line = data[:backtrace].first

        # template exceptions have the line number and filename as the first element in backtrace
        if (matched = first_line.match(/on line #(\d*) of (.*)/i))
          backtrace_hash = {
            line: matched[1],
            file: matched[2]
          }
        else
          backtrace_hash = Hash[* [:file, :line].zip(first_line.split(':')[0..1]).flatten]
        end

        data[:location].merge!(backtrace_hash)
      end
    end

    def clean_exception_data(data)
      if (as_array = data[:backtrace].to_a).size == 1
        data[:backtrace] = as_array.first.to_s.split(/\n\s*/)
      end

      if data[:request].is_a?(Hash) && data[:request][:params].is_a?(Hash)
        data[:request][:params] = deep_clean_hash(data[:request][:params])
      end

      if data[:environment].is_a?(Hash)
        data[:environment] = clean_environment(data[:environment])
      end
    end

    def clean_environment(env)
      Hash[ env.map do |k, v|
        [k, v] if !"#{k}: #{v}".in?(ENVIRONMENT_OMIT) && ENVIRONMENT_ALLOWLIST.any? { |regex| k =~ regex }
      end.compact ]
    end

    def deep_clean_hash(hash)
      hash.is_a?(Hash) or return hash

      hash.build_hash do |k, v|
        value = v.is_a?(Hash) ? deep_clean_hash(v) : filter_sensitive_value(k, v)
        [k, value]
      end
    end

    def filter_sensitive_value(key, value)
      if key =~ /(password|oauth_token)/
        "[FILTERED]"
      elsif key == "rack.request.form_vars" && value.respond_to?(:match) && (captured_matches = value.match(/(.*)(password=)([^&]+)(.*)/)&.captures)
        [*captured_matches[0..1], "[FILTERED]", *captured_matches[3..-1]].join
      else
        value
      end
    end

    #
    # Pull certain fields out of the controller and add to the data hash.
    #
    def extract_and_merge_controller_data(data)
      if @controller
        data[:request] = {
          params: @controller.request.parameters.to_hash,
          rails_root: defined?(Rails) && defined?(Rails.root) ? Rails.root : "Rails.root not defined. Is this a test environment?",
          url: @controller.complete_request_uri
        }
        data[:environment].merge!(@controller.request.env.to_hash)

        @controller.session[:fault_in_session]
        data[:session] = {
          key: @controller.request.session_options[:id],
          data: @controller.session.to_hash
        }
      end
    end

    def customize_from_data_callback(data)
      if @data_callback
        # the expectation is that if the caller passed a block then they will be
        # doing their own merge of hash values into data
        begin
          @data_callback.call(data)
        rescue Exception => ex
          data.merge!(environment: "Exception in yield: #{ex.class}:#{ex}")
        end
      end
    end

    def stringify_sections(data)
      SECTIONS.each { |section| add_to_s(data[section]) if data[section].is_a?(Hash) }
    end

    def unstringify_sections(data)
      SECTIONS.each do |section|
        if data[section].is_a?(Hash) && data[section].key?(:to_s)
          data[section] = data[section].dup
          data[section].delete(:to_s)
        end
      end
    end

    def add_to_s(data_section)
      data_section[:to_s] = dump_hash(data_section)
    end

    def dump_hash(h, indent_level = 0)
      result = +""
      h&.sort { |a, b| a.to_s <=> b.to_s }&.each do |key, value|
          result << ' ' * (2 * indent_level)
          result << "#{key}:"
          case value
          when Hash
            result << "\n" << dump_hash(value, indent_level + 1)
          else
            result << " #{value}\n"
          end
        end
      result
    end

    def enhanced_data_to_honeybadger_context
      data = enhanced_data.dup
      data[:server] = ExceptionHandling.server_name
      data[:exception_context] = deep_clean_hash(@exception_context) if @exception_context.present?
      data[:log_context] = @log_context
      unstringify_sections(data)
      context_data = HONEYBADGER_CONTEXT_SECTIONS.reduce({}) do |context, section|
        if data[section].present?
          context[section] = data[section]
        end
        context
      end
      context_data
    end
  end
end
