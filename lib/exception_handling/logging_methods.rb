# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/module/delegation.rb'

module ExceptionHandling
  module LoggingMethods # included on models and controllers
    extend ActiveSupport::Concern

    protected

    delegate :log_error_rack, :log_warning, :log_info, :log_debug, :escalate_error, :escalate_warning, :ensure_escalation, :alert_warning, :log_error, to: ExceptionHandling

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
  end
end
