# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/module/delegation.rb'

module ExceptionHandling
  module LoggingMethods # included on models and controllers
    extend ActiveSupport::Concern

    protected

    delegate :log_error_rack, :log_warning, :log_info, :log_debug, :escalate_error, :escalate_warning, :ensure_escalation, :alert_warning, to: ExceptionHandling

    def log_error(exception_or_string, exception_context = '')
      controller = self if respond_to?(:request) && respond_to?(:session)
      ExceptionHandling.log_error(exception_or_string, exception_context, controller)
    end

    def ensure_safe(exception_context = "")
      yield
    rescue => ex
      log_error ex, exception_context
      nil
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
  end
end
