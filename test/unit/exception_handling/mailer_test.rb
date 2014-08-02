require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class MailerTest < ActionMailer::TestCase

    include ActionDispatch::Assertions::SelectorAssertions
    tests ExceptionHandling::Mailer

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling::Mailer" do
      setup do
        ExceptionHandling.email_environment = 'Test'
        ExceptionHandling.sender_address = %("Test Exception Mailer" <null_exception@invoca.com>)
        ExceptionHandling.exception_recipients = ['test_exception@invoca.com']
        ExceptionHandling.escalation_recipients = ['test_escalation@invoca.com']
      end

      should "deliver" do
        #ActionMailer::Base.delivery_method = :smtp
        result = ExceptionHandling::Mailer.exception_notification({ :error => "Test Error."}).deliver
        assert_match /Test Error./, result.body.to_s
        assert_equal_with_diff ['test_exception@invoca.com'], result.to
        assert_emails 1
      end

      context "log_parser_exception_notification" do
        should "send with string" do
          result = ExceptionHandling::Mailer.log_parser_exception_notification("This is my fake error", "My Fake Subj").deliver
          assert_equal "Test exception: My Fake Subj: This is my fake error", result.subject
          assert_match(/This is my fake error/, result.body.to_s)
          assert_emails 1
        end
      end

      context "escalation_notification" do
        should "send all the information" do
          ExceptionHandling.email_environment = 'Staging Full'
          ExceptionHandling.server_name = 'test-fe3'

          ExceptionHandling::Mailer.escalation_notification("Your Favorite <b>Feature<b> Failed", :error_string => "It failed because of an error\n <i>More Info<i>", :timestamp => 1234567 ).deliver

          assert_emails 1
          result = ActionMailer::Base.deliveries.last
          body_html = HTML::Document.new(result.body.to_s)
          assert_equal_with_diff ['test_escalation@invoca.com'], result.to
          assert_equal ["Test Escalation Mailer <null_escalation@invoca.com>"], result[:from].formatted
          assert_equal "Staging Full Escalation: Your Favorite <b>Feature<b> Failed", result.subject
          assert_select body_html.root, "html" do
            assert_select "title", "Exception Escalation"
            assert_select "body br", { :count => 4 }, result.body.to_s # plus 1 for the multiline summary
            assert_select "body h3", "Your Favorite &lt;b&gt;Feature&lt;b&gt; Failed", result.body.to_s
            assert_select "body", /1234567/
            assert_select "body", /It failed because of an error\n &lt;i&gt;More Info&lt;i&gt;/
            assert_select "body", /test-fe3/
            #assert_select "body", /#{Web::Application::GIT_REVISION}/
          end
        end

        should "use defaults for missing fields" do
          result = ExceptionHandling::Mailer.escalation_notification("Your Favorite Feature Failed", :error_string => "It failed because of an error\n More Info")
          body_html = HTML::Document.new(result.body.to_s)

          assert_equal_with_diff ['test_escalation@invoca.com'], result.to
          assert_equal ["null_escalation@invoca.com"], result.from
          assert_equal 'Test Escalation: Your Favorite Feature Failed', result.subject
          assert_select body_html.root, "html" do
            assert_select "body i", true, result.body.to_s do |is|
              assert_select is[0], "i", 'no error #'
            end
          end
        end
      end
    end

  end
end