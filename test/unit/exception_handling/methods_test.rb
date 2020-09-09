# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../helpers/exception_helpers'

require "exception_handling/testing"

module ExceptionHandling
  class MethodsTest < ActiveSupport::TestCase
    include ExceptionHelpers

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling::Methods" do
      setup do
        @controller = Testing::ControllerStub.new
        ExceptionHandling.stub_handler = nil
      end

      context "#log_warning" do
        should "be available to the controller" do
          assert @controller.methods.include?(:log_warning)
        end
      end
    end

    context  "included deprecation" do
      setup do
        mock_deprecation_3_0
      end

      should "deprecate when no around_filter in included hook" do
        k = Class.new
        k.include ExceptionHandling::Methods
      end

      should "deprecate controller around_filter in included hook" do
        controller = Class.new
        class << controller
          def around_filter(*)
          end
        end
        controller.include ExceptionHandling::Methods
      end
    end

    private

    def mock_deprecation_3_0
      mock(STDERR).puts(/DEPRECATION WARNING: ExceptionHandling::Methods is deprecated and will be removed from exception_handling 3\.0/)
    end
  end
end
