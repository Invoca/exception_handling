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

      should "set the around filter" do
        assert_equal :set_current_controller, Testing::ControllerStub.around_filter_method
        assert_nil ExceptionHandling.current_controller
        @controller.simulate_around_filter do
          assert_equal @controller, ExceptionHandling.current_controller
        end
        assert_nil ExceptionHandling.current_controller
      end

      should "use the current_controller when available" do
        capture_notifications

        mock(ExceptionHandling.logger).fatal(/blah/, anything)
        @controller.simulate_around_filter do
          ExceptionHandling.log_error(ArgumentError.new("blah"))
          assert_equal 1, sent_notifications.size, sent_notifications.inspect
          assert_match(@controller.request.request_uri, sent_notifications.last.enhanced_data['request'].to_s)
        end
      end

      should "report long running controller action" do
        assert_equal 2, @controller.send(:long_controller_action_timeout)
        mock(ExceptionHandling).log_error(/Long controller action detected in #{@controller.class.name.split("::").last}::test_action/, anything, anything)
        @controller.simulate_around_filter do
          sleep(3)
        end
      end

      should "not report long running controller actions if it is less than the timeout" do
        assert_equal 2, @controller.send(:long_controller_action_timeout)
        stub(ExceptionHandling).log_error { flunk "Should not timeout" }
        @controller.simulate_around_filter do
          sleep(1)
        end
      end

      should "default long running controller action(300/30 for test/prod)" do
        class DummyController
          include ExceptionHandling::LoggingMethods
        end

        controller = DummyController.new

        Rails.env = 'production'
        assert_equal 30, controller.send(:long_controller_action_timeout)

        Rails.env = 'test'
        assert_equal 300, controller.send(:long_controller_action_timeout)
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
