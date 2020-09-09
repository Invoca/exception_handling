# frozen_string_literal: true

require 'active_support/concern'
require_relative 'logging_methods'

module ExceptionHandling
  module Methods # included on models and controllers
    extend ActiveSupport::Concern
    include ExceptionHandling::LoggingMethods

    protected

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
      if respond_to? :around_filter
        Deprecation3_0.deprecation_warning('around_filter definition when ::Methods is included into Rails Controllers', 'set your own around_filter to set logging context')
        around_filter :set_current_controller
      end
    end

    class_methods do
      def set_long_controller_action_timeout(timeout)
        define_method(:long_controller_action_timeout) { timeout }
        protected :long_controller_action_timeout
      end
    end
  end
end
