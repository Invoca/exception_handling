# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)

module ExceptionHandling
  describe LogErrorStub do

    include LogErrorStub

    context "while running tests" do
      before do
        setup_log_error_stub
      end

      after do
        teardown_log_error_stub
      end

      it "raise an error when log_error and log_warning are called" do
        begin
          ExceptionHandling.log_error("Something happened")
          flunk
        rescue Exception => ex # LogErrorStub::UnexpectedExceptionLogged => ex
          expect(ex.to_s.starts_with?("StandardError: Something happened")).to be_truthy
        end

        begin
          class ::RaisedError < StandardError; end
          raise ::RaisedError, "This should raise"
        rescue => ex
          begin
            ExceptionHandling.log_error(ex)
          rescue LogErrorStub::UnexpectedExceptionLogged => ex
            expect(ex.to_s.starts_with?("RaisedError: This should raise")).to be_truthy
          end
        end
      end

      it "allow for the regex specification of an expected exception to be ignored" do
        exception_pattern = /StandardError: This is a test error/
        expect(exception_whitelist).to be_nil  # test that exception expectations are cleared
        expects_exception(exception_pattern)
        expect(exception_whitelist[0][0]).to eq(exception_pattern)
        begin
          ExceptionHandling.log_error("This is a test error")
        rescue StandardError
          flunk # Shouldn't raise an error in this case
        end
      end

      it "allow for the string specification of an expected exception to be ignored" do
        exception_pattern = "StandardError: This is a test error"
        expect(exception_whitelist).to be_nil # test that exception expectations are cleared
        expects_exception(exception_pattern)
        expect(exception_whitelist[0][0]).to eq(exception_pattern)
        begin
          ExceptionHandling.log_error("This is a test error")
        rescue StandardError
          flunk # Shouldn't raise an error in this case
        end
      end

      it "allow multiple errors to be ignored" do
        class IgnoredError < StandardError; end
        expect(exception_whitelist).to be_nil # test that exception expectations are cleared
        expects_exception(/StandardError: This is a test error/)
        expects_exception(/IgnoredError: This should be ignored/)
        ExceptionHandling.log_error("This is a test error")
        begin
          raise IgnoredError, "This should be ignored"
        rescue IgnoredError => ex
          ExceptionHandling.log_error(ex)
        end
      end

      it "expect exception twice if declared twice" do
        expects_exception(/StandardError: ERROR: I love lamp/)
        expects_exception(/StandardError: ERROR: I love lamp/)
        ExceptionHandling.log_error("ERROR: I love lamp")
        ExceptionHandling.log_error("ERROR: I love lamp")
      end
    end

    context "teardown_log_error_stub" do
      it "support MiniTest framework for adding a failure" do
        expects_exception(/foo/)

        mock(self).is_mini_test?.returns { true }

        mock(self).flunk("log_error expected 1 times with pattern: 'foo' found 0")
        teardown_log_error_stub

        self.exception_whitelist = nil
      end

      it "support Test::Unit framework for adding a failure" do
        expects_exception(/foo/)

        mock(self).is_mini_test?.returns { false }

        mock(self).add_failure("log_error expected 1 times with pattern: 'foo' found 0")
        teardown_log_error_stub

        self.exception_whitelist = nil
      end
    end
  end
end
