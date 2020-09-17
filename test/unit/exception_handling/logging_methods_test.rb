# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../helpers/exception_helpers'

require "exception_handling/testing"

module ExceptionHandling
  class LoggingMethodsTest < ActiveSupport::TestCase
    include ExceptionHelpers

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling::LoggingMethods" do
      setup do
        @controller = Testing::LoggingMethodsControllerStub.new
        ExceptionHandling.stub_handler = nil
      end

      context "#log_warning" do
        should "be available to the controller" do
          klass = Class.new
          klass.include ExceptionHandling::LoggingMethods
          instance = klass.new
          assert instance.methods.include?(:log_warning)
        end

        should "call ExceptionHandling#log_warning" do
          mock(ExceptionHandling).log_warning("Hi mom")
          @controller.send(:log_warning, "Hi mom")
        end
      end
    end
  end
end
