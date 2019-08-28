# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)

module ExceptionHandling
  class MailerTest < ActionMailer::TestCase

    include ::Rails::Dom::Testing::Assertions::SelectorAssertions
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

      context "log_parser_exception_notification" do
        should "send with string" do
          result = ExceptionHandling::Mailer.log_parser_exception_notification("This is my fake error", "My Fake Subj").deliver_now
          assert_equal "Test exception: My Fake Subj: This is my fake error", result.subject
          assert_match(/This is my fake error/, result.body.to_s)
          assert_emails 1
        end
      end

      context "escalation_notification" do
        setup do
          def document_root_element
            @body_html.root
          end
        end

        should "send all the information" do
          ExceptionHandling.email_environment = 'Staging Full'
          ExceptionHandling.server_name = 'test-fe3'

          ExceptionHandling::Mailer.escalation_notification("Your Favorite <b>Feature<b> Failed", error_string: "It failed because of an error\n <i>More Info<i>", timestamp: 1234567).deliver_now

          assert_emails 1
          result = ActionMailer::Base.deliveries.last
          @body_html = Nokogiri::HTML(result.body.to_s)
          assert_equal_with_diff ['test_escalation@invoca.com'], result.to
          assert_equal ["Test Escalation Mailer <null_escalation@invoca.com>"], result[:from].formatted
          assert_equal "Staging Full Escalation: Your Favorite <b>Feature<b> Failed", result.subject
          assert_select "title", "Exception Escalation"
          assert_select "html" do
            assert_select "body br", { count: 4 }, result.body.to_s # plus 1 for the multiline summary
            assert_select "body h3", "Your Favorite <b>Feature<b> Failed", result.body.to_s
            assert_select "body", /1234567/
            assert_select "body", /It failed because of an error/
            assert_select "body", /\n <i>More Info<i>/
            assert_select "body", /test-fe3/
            # assert_select "body", /#{Web::Application::GIT_REVISION}/
          end
        end

        should "use defaults for missing fields" do
          result = ExceptionHandling::Mailer.escalation_notification("Your Favorite Feature Failed", error_string: "It failed because of an error\n More Info")
          @body_html = Nokogiri::HTML(result.body.to_s)

          assert_equal_with_diff ['test_escalation@invoca.com'], result.to
          assert_equal ["null_escalation@invoca.com"], result.from
          assert_equal 'Test Escalation: Your Favorite Feature Failed', result.subject
          assert_select "html" do
            assert_select "body i", true, result.body.to_s do |is|
              assert_select is, "i", 'no error #'
            end
          end
        end

        context "ExceptionHandling.escalate_to_production_support" do
          setup do
            Time.now_override = Time.parse('1986-5-21 4:17 am UTC')
          end

          should "notify production support" do
            subject = "Runtime Error found!"
            exception = RuntimeError.new("Test")
            recipients = ["prodsupport@example.com"]

            ExceptionHandling.production_support_recipients = recipients
            ExceptionHandling.last_exception_timestamp = Time.now.to_i

            mock(ExceptionHandling).escalate_custom(subject, exception, Time.now.to_i, recipients)
            ExceptionHandling.escalate_to_production_support(exception, subject)
          end
        end
      end
    end

  end
end
