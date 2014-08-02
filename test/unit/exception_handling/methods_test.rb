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

      teardown do
        Time.now_override = nil
      end

      should "set the around filter" do
        assert_equal :set_current_controller, Testing::ControllerStub.around_filter_method
        assert_nil ExceptionHandling.current_controller
        @controller.simulate_around_filter( ) do
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
        # This was the original stub:
        # Rails.expects(:env).times(2).returns('production')
        # but this stubbing approach no longer works
        # Rails is setting the long controller timeout on module load
        # in exception_handling.rb - that happens before this test ever gets run
        # we can set Rails.env here, which we do, because it affects part of the real-time
        # logic check for whether to raise (which we want). To overcome the setting
        # on the long controller timeout I have set the Time.now_override to 1.day.from_now
        # instead of 1.hour.from_now
        mock(ExceptionHandling).log_error(/Long controller action detected in #{@controller.class.name.split("::").last}::test_action/, anything, anything)
        @controller.simulate_around_filter( ) do
          Time.now_override = 1.day.from_now
        end
      end
    end

  end
end