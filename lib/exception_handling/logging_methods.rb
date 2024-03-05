# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/module/delegation.rb'

module ExceptionHandling
  module LoggingMethods # included on models and controllers
    extend ActiveSupport::Concern

    protected

    delegate :log_error_rack, :log_warning, :log_info, :log_debug, :log_error, to: ExceptionHandling

    def ensure_safe(exception_context = "")
      yield
    rescue => ex
      log_error ex, exception_context
      nil
    end
  end
end
