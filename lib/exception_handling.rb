# frozen_string_literal: true

require 'digest'
require 'timeout'
require 'active_support'
require 'active_support/core_ext'
require 'contextual_logger'

require 'invoca/utils'

require 'exception_handling/methods'
require 'exception_handling/log_stub_error'
require 'exception_handling/exception_description'
require 'exception_handling/exception_catalog'
require 'exception_handling/exception_info'
require 'exception_handling/escalate_callback'

_ = ActiveSupport::HashWithIndifferentAccess

module ExceptionHandling # never included
  class Warning < StandardError; end
  class ClientLoggingError < StandardError; end

  SUMMARY_THRESHOLD = 5
  SUMMARY_PERIOD = 60 * 60 # 1.hour

  AUTHENTICATION_HEADERS = ['HTTP_AUTHORIZATION', 'X-HTTP_AUTHORIZATION', 'X_HTTP_AUTHORIZATION', 'REDIRECT_X_HTTP_AUTHORIZATION'].freeze
  HONEYBADGER_STATUSES   = [:success, :failure, :skipped].freeze

  Deprecation3_0 = ActiveSupport::Deprecation.new('3.0', 'exception_handling')

  class << self

    #
    # required settings
    #
    attr_writer :server_name

    def server_name
      @server_name or raise ArgumentError, "You must assign a value to #{name}.server_name"
    end

    def configured?
      !@logger.nil?
    end

    def logger
      @logger or raise ArgumentError, "You must assign a value to #{name}.logger"
    end

    def logger=(logger)
      logger.nil? || logger.is_a?(ContextualLogger::LoggerMixin) or raise ArgumentError,
                                                                          "The logger must be a ContextualLogger::LoggerMixin, not a #{logger.class}"
      @logger = logger
      EscalateCallback.register_if_configured!
    end

    def default_metric_name(exception_data, exception, treat_like_warning, include_prefix: true)
      include_prefix and Deprecation3_0.deprecation_warning("the 'expection_handling.' prefix in ExceptionHandling::default_metric_name",
                                                            "do not rely on metric names including the 'exception_handling.' prefix.")

      metric_name = if exception_data['metric_name']
                      exception_data['metric_name']
                    elsif exception.is_a?(ExceptionHandling::Warning)
                      "warning"
                    elsif treat_like_warning
                      exception_name = "_#{exception.class.name.split('::').last}" if exception.present?
                      "unforwarded_exception#{exception_name}"
                    else
                      "exception"
                    end

      "#{'exception_handling.' if include_prefix}#{metric_name}"
    end

    def default_honeybadger_metric_name(honeybadger_status)
      metric_name = if honeybadger_status.in?(HONEYBADGER_STATUSES)
                      honeybadger_status
                    else
                      :unknown_status
                    end
      "exception_handling.honeybadger.#{metric_name}"
    end

    #
    # optional settings
    #
    attr_accessor :production_support_recipients
    attr_accessor :environment
    attr_accessor :custom_data_hook
    attr_accessor :post_log_error_hook
    attr_accessor :stub_handler

    attr_reader :filter_list_filename
    attr_reader :honeybadger_auto_tagger

    @filter_list_filename = "./config/exception_filters.yml"

    def filter_list_filename=(filename)
      @filter_list_filename = filename
      @exception_catalog = nil
    end

    def exception_catalog
      @exception_catalog ||= ExceptionCatalog.new(@filter_list_filename)
    end

    # rubocop:disable Style/TrivialAccessors
    # @param value [Proc|nil] Proc that accepts 1 parameter that will be the exception object or nil to disable the auto-tagger.
    #                         The proc is always expected to return an array of strings. The array can be empty.
    def honeybadger_auto_tagger=(value)
      @honeybadger_auto_tagger = value
    end
    # rubocop:enable Style/TrivialAccessors

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
    #   may send to honeybadger
    #
    # but not during functional tests, when rack middleware is not used
    #
    def log_error_rack(exception, env, _rack_filter)
      timestamp = set_log_error_timestamp
      exception_info = ExceptionInfo.new(exception, env, timestamp)

      if stub_handler
        stub_handler.handle_stub_log_error(exception_info.data)
      else
        # TODO: add a more interesting custom description, like:
        # custom_description = ": caught and processed by Rack middleware filter #{rack_filter}"
        # which would be nice, but would also require changing quite a few tests
        custom_description = ""
        write_exception_to_log(exception, custom_description, timestamp)

        send_external_notifications(exception_info)

        nil
      end
    end

    #
    # Normal Operation:
    #   Called directly by our code, usually from rescue blocks.
    #   Writes to log file and may send to honeybadger
    #
    # TODO: the **log_context means we can never have context named treat_like_warning. In general, keyword args will be conflated with log_context.
    # Ideally we'd separate to log_context from the other keywords so they don't interfere in any way. Or have no keyword args.
    #
    # Functional Test Operation:
    #   Calls into handle_stub_log_error and returns. no log file. no honeybadger
    #
    def log_error(exception_or_string, exception_context = '', controller = nil, treat_like_warning: false, **log_context, &data_callback)
      ex = make_exception(exception_or_string)
      timestamp = set_log_error_timestamp
      exception_info = ExceptionInfo.new(ex, exception_context, timestamp,
                                         controller: controller || current_controller, data_callback: data_callback,
                                         log_context: log_context)

      if stub_handler
        stub_handler.handle_stub_log_error(exception_info.data)
      else
        write_exception_to_log(ex, exception_context, timestamp, log_context)
        external_notification_results = unless treat_like_warning || ex.is_a?(Warning)
                                          send_external_notifications(exception_info)
                                        end || {}
        execute_custom_log_error_callback(exception_info.enhanced_data.merge(log_context: log_context), exception_info.exception, treat_like_warning, external_notification_results)
      end

      ExceptionHandling.last_exception_timestamp
    rescue LogErrorStub::UnexpectedExceptionLogged, LogErrorStub::ExpectedExceptionNotLogged
      raise
    rescue Exception => ex
      warn("ExceptionHandlingError: log_error rescued exception while logging #{exception_context}: #{exception_or_string}:\n#{ex.class}: #{ex.message}\n#{ex.backtrace.join("\n")}")
      write_exception_to_log(ex, "ExceptionHandlingError: log_error rescued exception while logging #{exception_context}: #{exception_or_string}", timestamp)
    ensure
      ExceptionHandling.last_exception_timestamp
    end

    #
    # Write an exception out to the log file using our own custom format.
    #
    def write_exception_to_log(ex, exception_context, timestamp, log_context = {})
      ActiveSupport::Deprecation.silence do
        log_message = "#{exception_context}\n#{ex.class}: (#{encode_utf8(ex.message.to_s)}):\n  " + clean_backtrace(ex).join("\n  ") + "\n\n"

        if ex.is_a?(Warning)
          ExceptionHandling.logger.warn("\nExceptionHandlingWarning (Warning:#{timestamp}) #{log_message}", **log_context)
        else
          ExceptionHandling.logger.fatal("\nExceptionHandlingError (Error:#{timestamp}) #{log_message}", **log_context)
        end
      end
    end

    #
    # Send notifications to configured external services
    #
    def send_external_notifications(exception_info)
      results = {}
      if honeybadger_defined?
        results[:honeybadger_status] = send_exception_to_honeybadger_unless_filtered(exception_info)
      end
      results
    end

    # Returns :success or :failure or :skipped
    def send_exception_to_honeybadger_unless_filtered(exception_info)
      if exception_info.send_to_honeybadger?
        send_exception_to_honeybadger(exception_info)
      else
        log_info("Filtered exception using '#{exception_info.exception_description.filter_name}'; not sending notification to Honeybadger")
        :skipped
      end
    end

    #
    # Log exception to honeybadger.io.
    #
    # Returns :success or :failure
    #
    def send_exception_to_honeybadger(exception_info)
      exception             = exception_info.exception
      exception_description = exception_info.exception_description

      # Note: Both commas and spaces are treated as delimiters for the :tags string. Space-delimiters are not officially documented.
      # https://github.com/honeybadger-io/honeybadger-ruby/pull/422
      tags = (honeybadger_auto_tags(exception) + exception_info.honeybadger_tags).join(' ')
      response = Honeybadger.notify(error_class: exception_description ? exception_description.filter_name : exception.class.name,
                                    error_message: exception.message.to_s,
                                    exception:     exception,
                                    context:       exception_info.honeybadger_context_data,
                                    controller:    exception_info.controller_name,
                                    tags:          tags)
      response ? :success : :failure
    rescue Exception => ex
      warn("ExceptionHandling.send_exception_to_honeybadger rescued exception while logging #{exception_info.exception_context}:\n#{exception.class}: #{exception.message}:\n#{ex.class}: #{ex.message}\n#{ex.backtrace.join("\n")}")
      write_exception_to_log(ex, "ExceptionHandling.send_exception_to_honeybadger rescued exception while logging #{exception_info.exception_context}:\n#{exception.class}: #{exception.message}", exception_info.timestamp)
      :failure
    end

    # @param exception [Exception]
    #
    # @return [Array<String>]
    def honeybadger_auto_tags(exception)
      @honeybadger_auto_tagger&.call(exception) || []
    rescue => ex
      traces = ex.backtrace.join("\n")
      message = "Unable to execute honeybadger_auto_tags callback. #{ExceptionHandling.encode_utf8(ex.message.to_s)} #{traces}\n"
      ExceptionHandling.log_info(message)
      []
    end

    #
    # Check if Honeybadger defined.
    #
    def honeybadger_defined?
      Object.const_defined?("Honeybadger")
    end

    #
    # Expects passed in hash to only include keys which be directly set on the Honeybadger config
    #
    def enable_honeybadger(**config)
      Bundler.require(:honeybadger)
      Honeybadger.configure do |config_klass|
        config.each do |k, v|
          if k == :before_notify
            config_klass.send(k, v)
          else
            config_klass.send(:"#{k}=", v)
          end
        end
      end
    end

    def log_warning(message, **log_context)
      warning = Warning.new(message)
      warning.set_backtrace([])
      log_error(warning, **log_context)
    end

    def log_info(message, **log_context)
      ExceptionHandling.logger.info(message, **log_context)
    end

    def log_debug(message, **log_context)
      ExceptionHandling.logger.debug(message, **log_context)
    end

    def ensure_safe(exception_context = "", **log_context)
      yield
    rescue => ex
      log_error(ex, exception_context, **log_context)
      nil
    end

    def ensure_completely_safe(exception_context = "", **log_context)
      yield
    rescue SystemExit, SystemStackError, NoMemoryError, SecurityError, SignalException
      raise
    rescue Exception => ex
      log_error(ex, exception_context, **log_context)
      nil
    end

    def set_log_error_timestamp
      ExceptionHandling.last_exception_timestamp = Time.now.to_i
    end

    def trace_timing(description)
      result = nil
      time = Benchmark.measure do
        result = yield
      end
      log_info "#{description} %.4fs  " % time.real
      result
    end

    def log_periodically(exception_key, interval, message, **log_context)
      self.periodic_exception_intervals ||= {}
      last_logged = self.periodic_exception_intervals[exception_key]
      if !last_logged || ((last_logged + interval) < Time.now)
        log_error(message, **log_context)
        self.periodic_exception_intervals[exception_key] = Time.now
      end
    end

    def encode_utf8(string)
      string.encode('UTF-8',
                    replace: '?',
                    undef: :replace,
                    invalid: :replace)
    end

    def clean_backtrace(exception)
      backtrace = if exception.backtrace.nil?
                    ['<no backtrace>']
                  elsif exception.is_a?(ClientLoggingError)
                    exception.backtrace
                  elsif defined?(Rails) && defined?(Rails.backtrace_cleaner)
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

    def execute_custom_log_error_callback(exception_data, exception, treat_like_warning, external_notification_results)
      if ExceptionHandling.post_log_error_hook
        honeybadger_status = external_notification_results[:honeybadger_status] || :skipped
        ExceptionHandling.post_log_error_hook.call(exception_data, exception, treat_like_warning, honeybadger_status)
      end
    rescue Exception => ex
      # can't call log_error here or we will blow the call stack
      ex_message = encode_utf8(ex.message.to_s)
      ex_backtrace = ex.backtrace.each { |l| "#{l}\n" }
      log_info("Unable to execute custom log_error callback. #{ex_message} #{ex_backtrace}")
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

  EscalateCallback.register_if_configured!
end
