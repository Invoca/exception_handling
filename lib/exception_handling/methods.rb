# frozen_string_literal: true

require 'active_support/concern'
require_relative 'logging_methods'

module ExceptionHandling
  module Methods # included on models and controllers
    extend ActiveSupport::Concern
    include ExceptionHandling::LoggingMethods

    protected

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
      if time.real > long_controller_action_timeout && !['development', 'test'].include?(ExceptionHandling.environment)
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

    class_methods do
      def set_long_controller_action_timeout(timeout)
        define_method(:long_controller_action_timeout) { timeout }
        protected :long_controller_action_timeout
      end
    end
  end
end
