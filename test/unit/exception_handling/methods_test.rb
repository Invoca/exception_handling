require File.expand_path('../../../test_helper',  __FILE__)

require "exception_handling/testing"

module ExceptionHandling
  class MethodsTest < ActiveSupport::TestCase

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling.Methods" do
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
        mock(ExceptionHandling.logger).fatal(/blah/)
        @controller.simulate_around_filter do
          ExceptionHandling.log_error( ArgumentError.new("blah") )
          mail = ActionMailer::Base.deliveries.last
          assert_match( @controller.request.request_uri, mail.body.to_s )
        # assert_match( Username.first.username.to_s, mail.body.to_s ) if defined?(Username)
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
          include ExceptionHandling::Methods
        end

        controller = DummyController.new

        Rails.env = 'production'
        assert_equal 30, controller.send(:long_controller_action_timeout)

        Rails.env = 'test'
        assert_equal 300, controller.send(:long_controller_action_timeout)
      end

      context "#log_warning" do
        should "be available to the controller" do
          assert_equal true, @controller.methods.include?(:log_warning)
        end

        should "call ExceptionHandling#log_warning" do
          mock(ExceptionHandling).log_warning("Hi mom")
          @controller.send(:log_warning, "Hi mom")
        end
      end
    end

  end
end
