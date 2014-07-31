require File.expand_path('../../../test_helper',  __FILE__)

class LogErrorStubTest < ActiveSupport::TestCase
  include LogErrorStub

  context "while running tests" do
    setup do
      setup_log_error_stub
    end

    teardown do
      teardown_log_error_stub
    end

    should "raise an error when log_error and log_warning are called" do
      begin
        ExceptionHandling.log_error("Something happened")
        flunk
      rescue Exception => ex #LogErrorStub::UnexpectedExceptionLogged => ex
        assert ex.to_s.starts_with?("StandardError: Something happened"), ex.to_s
      end

      begin
        class ::RaisedError < StandardError; end
        raise ::RaisedError, "This should raise"
      rescue => ex
        begin
          ExceptionHandling.log_error(ex)
        rescue LogErrorStub::UnexpectedExceptionLogged => ex_inner
          assert ex_inner.to_s.starts_with?("RaisedError: This should raise"), ex_inner.to_s
        end
      end
    end

    should "allow for the regex specification of an expected exception to be ignored" do
      exception_pattern = /StandardError: This is a test error/
      assert_nil exception_whitelist # test that exception expectations are cleared
      expects_exception(exception_pattern)
      assert_equal exception_pattern, exception_whitelist[0][0]
      begin
        ExceptionHandling.log_error("This is a test error")
      rescue => ex
        flunk # Shouldn't raise an error in this case
      end
    end

    should "allow for the string specification of an expected exception to be ignored" do
      exception_pattern = "StandardError: This is a test error"
      assert_nil exception_whitelist # test that exception expectations are cleared
      expects_exception(exception_pattern)
      assert_equal exception_pattern, exception_whitelist[0][0]
      begin
        ExceptionHandling.log_error("This is a test error")
      rescue => ex
        flunk # Shouldn't raise an error in this case
      end
    end

    should "allow multiple errors to be ignored" do
      class IgnoredError < StandardError; end
      assert_nil exception_whitelist # test that exception expectations are cleared
      expects_exception(/StandardError: This is a test error/)
      expects_exception(/IgnoredError: This should be ignored/)
      ExceptionHandling.log_error("This is a test error")
      begin
        raise IgnoredError, "This should be ignored"
      rescue IgnoredError => ex
        ExceptionHandling.log_error(ex)
      end
    end

    should "expect exception twice if declared twice" do
      expects_exception(/StandardError: ERROR: I love lamp/)
      expects_exception(/StandardError: ERROR: I love lamp/)
      ExceptionHandling.log_error("ERROR: I love lamp")
      ExceptionHandling.log_error("ERROR: I love lamp")
    end
  end

end
