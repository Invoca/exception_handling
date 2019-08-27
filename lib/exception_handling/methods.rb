# frozen_string_literal: true

require 'active_support/concern'

module ExceptionHandling
  module Methods # included on models and controllers
    extend ActiveSupport::Concern

    protected

    def log_error(exception_or_string, exception_context = '')
      controller = self if respond_to?(:request) && respond_to?(:session)
      ExceptionHandling.log_error(exception_or_string, exception_context, controller)
    end

    def log_error_rack(exception_or_string, exception_context = '', rack_filter = '')
      ExceptionHandling.log_error_rack(exception_or_string, exception_context, rack_filter)
    end

    def log_warning(message)
      ExceptionHandling.log_warning(message)
    end

    def log_info(message)
      ExceptionHandling.logger.info(message)
    end

    def log_debug(message)
      ExceptionHandling.logger.debug(message)
    end

    def ensure_safe(exception_context = "")
      yield
    rescue => ex
      log_error ex, exception_context
      nil
    end

    def escalate_error(exception_or_string, email_subject)
      ExceptionHandling.escalate_error(exception_or_string, email_subject)
    end

    def escalate_warning(message, email_subject)
      ExceptionHandling.escalate_warning(message, email_subject)
    end

    def ensure_escalation(*args)
      ExceptionHandling.ensure_escalation(*args) do
        yield
      end
    end

    def alert_warning(*args)
      ExceptionHandling.alert_warning(*args)
    end

    def ensure_alert(*args)
      ExceptionHandling.ensure_alert(*args) do
        yield
      end
    end

    def long_controller_action_timeout
      if defined?(Rails) && Rails.respond_to?(:env) && Rails.env == 'test'
        300
      else
        30
      end
    end

    def set_current_controller
      ExceptionHandling.current_controller = self
      result = nil
      time = Benchmark.measure do
        result = yield
      end
      if time.real > long_controller_action_timeout && !['development', 'test'].include?(ExceptionHandling.email_environment)
        name = begin
                 " in #{controller_name}::#{action_name}"
               rescue
                 " "
               end
        log_error("Long controller action detected#{name} %.4fs  " % time.real)
      end
      result
    ensure
      ExceptionHandling.current_controller = nil
    end

    included do
      around_filter :set_current_controller if respond_to? :around_filter
    end

    class_methods do
      def set_long_controller_action_timeout(timeout)
        define_method(:long_controller_action_timeout) { timeout }
        protected :long_controller_action_timeout
      end
    end
  end
end
