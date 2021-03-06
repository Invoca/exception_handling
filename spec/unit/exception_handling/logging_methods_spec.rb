# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)

require_relative '../../helpers/exception_helpers'

require "exception_handling/testing"

module ExceptionHandling
  describe LoggingMethods do
    include ExceptionHelpers

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling::LoggingMethods" do
      before do
        @controller = Testing::LoggingMethodsControllerStub.new
        ExceptionHandling.stub_handler = nil
      end

      context "#log_warning" do
        it "be available to the controller" do
          klass = Class.new
          klass.include ExceptionHandling::LoggingMethods
          instance = klass.new
          expect(instance.methods.include?(:log_warning)).to eq(true)
        end

        it "call ExceptionHandling#log_warning" do
          expect(ExceptionHandling).to receive(:log_warning).with("Hi mom")
          @controller.send(:log_warning, "Hi mom")
        end
      end
    end
  end
end
