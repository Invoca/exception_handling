require File.expand_path('../../test_helper',  __FILE__)
require_test_helper 'controller_helpers'
require_test_helper 'exception_helpers'

class ExceptionHandlingTest < ActiveSupport::TestCase
  include ControllerHelpers
  include ExceptionHelpers

  def dont_stub_log_error
    true
  end

  def append_organization_info_config(data)
    begin
      data[:user_details]                = {}
      data[:user_details][:username]     = "CaryP"
      data[:user_details][:organization] = "Invoca Engineering Dept."
    rescue Exception => e
      # don't let these out!
    end
  end

  def custom_data_callback_returns_nil_message_exception(data)
    raise_exception_with_nil_message
  end

  def log_error_callback(data, ex)
    @fail_count += 1
  end

  def log_error_callback_config(data, ex)
    @callback_data = data
    @fail_count += 1
  end

  def log_error_callback_with_failure(data, ex)
    raise "this should be rescued"
  end

  def log_error_callback_returns_nil_message_exception(data, ex)
    raise_exception_with_nil_message
  end

  module EventMachineStub
    class << self
      attr_accessor :block

      def schedule(&block)
        @block = block
      end
    end
  end

  class DNSResolvStub
    class << self
      attr_accessor :callback_block
      attr_accessor :errback_block

      def resolve(hostname)
        self
      end

      def callback(&block)
        @callback_block = block
      end

      def errback(&block)
        @errback_block = block
      end
    end
  end

  class SmtpClientStub
    class << self
      attr_reader :block
      attr_reader :last_method

      def errback(&block)
        @block = block
      end

      def send_hash
        @send_hash ||= {}
      end

      def send(hash)
        @last_method = :send
        send_hash.clear
        send_hash.merge!(hash)
        self
      end

      def asend(hash)
        send(hash)
        @last_method = :asend
        self
      end
    end
  end

  class SmtpClientErrbackStub < SmtpClientStub
  end

  class HoneybadgerStub
    def self.notify(data)
    end
  end

  context "#log_error" do
    setup do
      ExceptionHandling.mailer_send_enabled = true
    end

    should "log the info and not raise another exception when sending email fails" do
      9.times { ExceptionHandling.log_error('SomeError', 'Error Context') }
      mock(ExceptionHandling::Mailer).exception_notification(anything, anything, anything) { raise 'An Error' }
      mock(ExceptionHandling.logger) do |logger|
        logger.info(/ExceptionHandling.log_error_email rescued exception while logging StandardError: SomeError/)
      end
      stub($stderr).puts
      ExceptionHandling.log_error('SomeError', 'Error Context')
    end
  end

  context "configuration" do
    should "support a custom_data_hook" do
      ExceptionHandling.custom_data_hook = method(:append_organization_info_config)
      ExceptionHandling.ensure_safe("mooo") { raise "Some BS" }
      assert_match(/Invoca Engineering Dept./, ActionMailer::Base.deliveries[-1].body.to_s)
      ExceptionHandling.custom_data_hook = nil
    end

    should "support a log_error hook and pass exception data to it" do
      begin
        @fail_count = 0
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
        ExceptionHandling.ensure_safe("mooo") { raise "Some BS" }
        assert_equal 1, @fail_count
      ensure
        ExceptionHandling.post_log_error_hook = nil
      end

      assert_equal "this is used by a test", @callback_data["notes"]
      assert_match(/this is used by a test/, ActionMailer::Base.deliveries[-1].body.to_s)
    end

    should "support rescue exceptions from a log_error hook" do
      ExceptionHandling.post_log_error_hook = method(:log_error_callback_with_failure)
      log_info_messages = []
      stub(ExceptionHandling.logger).info.with_any_args do |message, _|
        log_info_messages << message
      end
      assert_nothing_raised { ExceptionHandling.ensure_safe("mooo") { raise "Some BS" } }
      assert log_info_messages.find { |message| message =~ /Unable to execute custom log_error callback/ }
      ExceptionHandling.post_log_error_hook = nil
    end

    should "handle nil message exceptions resulting from the log_error hook" do
      ExceptionHandling.post_log_error_hook = method(:log_error_callback_returns_nil_message_exception)
      log_info_messages = []
      stub(ExceptionHandling.logger).info.with_any_args do |message, _|
        log_info_messages << message
      end
      assert_nothing_raised { ExceptionHandling.ensure_safe("mooo") { raise "Some BS" } }
      assert log_info_messages.find { |message| message =~ /Unable to execute custom log_error callback/ }
      ExceptionHandling.post_log_error_hook = nil
    end

    should "handle nil message exceptions resulting from the custom data hook" do
      ExceptionHandling.custom_data_hook = method(:custom_data_callback_returns_nil_message_exception)
      log_info_messages = []
      stub(ExceptionHandling.logger).info.with_any_args do |message, _|
        log_info_messages << message
      end
      assert_nothing_raised { ExceptionHandling.ensure_safe("mooo") { raise "Some BS" } }
      assert log_info_messages.find { |message| message =~ /Unable to execute custom custom_data_hook callback/ }
      ExceptionHandling.custom_data_hook = nil
    end

  end

  context "Exception Handling" do
    setup do
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.send(:clear_exception_summary)
    end

    context "ExceptionHandling.ensure_safe" do
      should "log an exception with call stack if an exception is raised." do
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        ExceptionHandling.ensure_safe { raise ArgumentError.new("blah") }
      end

      should "log an exception with call stack if an ActionView template exception is raised." do
        mock(ExceptionHandling.logger).fatal(/\(Error:\d+\) ActionView::Template::Error  \(blah\):\n /)
        ExceptionHandling.ensure_safe { raise ActionView::TemplateError.new({}, ArgumentError.new("blah")) }
      end

      should "should not log an exception if an exception is not raised." do
        dont_allow(ExceptionHandling.logger).fatal
        ExceptionHandling.ensure_safe { ; }
      end

      should "return its value if used during an assignment" do
        dont_allow(ExceptionHandling.logger).fatal
        b = ExceptionHandling.ensure_safe { 5 }
        assert_equal 5, b
      end

      should "return nil if an exception is raised during an assignment" do
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        b = ExceptionHandling.ensure_safe { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "allow a message to be appended to the error when logged." do
        mock(ExceptionHandling.logger).fatal(/mooo \(blah\):\n.*exception_handling_test\.rb/)
        b = ExceptionHandling.ensure_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "only rescue StandardError and descendents" do
        assert_raise(Exception) { ExceptionHandling.ensure_safe("mooo") { raise Exception } }

        mock(ExceptionHandling.logger).fatal(/mooo \(blah\):\n.*exception_handling_test\.rb/)

        b = ExceptionHandling.ensure_safe("mooo") { raise StandardError.new("blah") }
        assert_nil b
      end
    end

    context "ExceptionHandling.ensure_completely_safe" do
      should "log an exception if an exception is raised." do
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        ExceptionHandling.ensure_completely_safe { raise ArgumentError.new("blah") }
      end

      should "should not log an exception if an exception is not raised." do
        mock(ExceptionHandling.logger).fatal.times(0)
        ExceptionHandling.ensure_completely_safe { ; }
      end

      should "return its value if used during an assignment" do
        mock(ExceptionHandling.logger).fatal.times(0)
        b = ExceptionHandling.ensure_completely_safe { 5 }
        assert_equal 5, b
      end

      should "return nil if an exception is raised during an assignment" do
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/) { nil }
        b = ExceptionHandling.ensure_completely_safe { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "allow a message to be appended to the error when logged." do
        mock(ExceptionHandling.logger).fatal(/mooo \(blah\):\n.*exception_handling_test\.rb/)
        b = ExceptionHandling.ensure_completely_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "rescue any instance or child of Exception" do
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        ExceptionHandling::ensure_completely_safe { raise Exception.new("blah") }
      end

      should "not rescue the special exceptions that Ruby uses" do
        [SystemExit, SystemStackError, NoMemoryError, SecurityError].each do |exception|
          assert_raise exception do
            ExceptionHandling.ensure_completely_safe do
              raise exception.new
            end
          end
        end
      end
    end

    context "ExceptionHandling.ensure_escalation" do
      should "log the exception as usual and send the proper email" do
        assert_equal 0, ActionMailer::Base.deliveries.count
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        ExceptionHandling.ensure_escalation( "Favorite Feature") { raise ArgumentError.new("blah") }
        assert_equal 2, ActionMailer::Base.deliveries.count
        email = ActionMailer::Base.deliveries.last
        assert_equal "#{ExceptionHandling.email_environment} Escalation: Favorite Feature", email.subject
        assert_match 'ArgumentError: blah', email.body.to_s
        assert_match ExceptionHandling.last_exception_timestamp.to_s, email.body.to_s
      end

      should "should not escalate if an exception is not raised." do
        assert_equal 0, ActionMailer::Base.deliveries.count
        dont_allow(ExceptionHandling.logger).fatal
        ExceptionHandling.ensure_escalation('Ignored') { ; }
        assert_equal 0, ActionMailer::Base.deliveries.count
      end

      should "log if the escalation email can not be sent" do
        any_instance_of(Mail::Message) do |message|
          mock(message).deliver
          mock(message).deliver { raise RuntimeError.new, "Delivery Error" }
        end
        mock(ExceptionHandling.logger) do |logger|
          logger.fatal(/first_test_exception/)
          logger.fatal(/safe_email_deliver .*Delivery Error/)
        end
        ExceptionHandling.ensure_escalation("Not Used") { raise ArgumentError.new("first_test_exception") }
        assert_equal 0, ActionMailer::Base.deliveries.count
      end
    end

    context "ExceptionHandling.ensure_alert" do
      should "log the exception as usual and fire a sensu event" do
        mock(ExceptionHandling::Sensu).generate_event("Favorite Feature", "test context\nblah")
        mock(ExceptionHandling.logger).fatal(/\(blah\):\n.*exception_handling_test\.rb/)
        ExceptionHandling.ensure_alert('Favorite Feature', 'test context') { raise ArgumentError.new("blah") }
      end

      should "should not send sensu event if an exception is not raised." do
        dont_allow(ExceptionHandling.logger).fatal
        dont_allow(ExceptionHandling::Sensu).generate_event
        ExceptionHandling.ensure_alert('Ignored', 'test context') { ; }
      end

      should "log if the sensu event could not be sent" do
        mock(ExceptionHandling::Sensu).send_event(anything) { raise "Failed to send" }
        mock(ExceptionHandling.logger) do |logger|
          logger.fatal(/first_test_exception/)
          logger.fatal(/Failed to send/)
        end
        ExceptionHandling.ensure_alert("Not Used", 'test context') { raise ArgumentError.new("first_test_exception") }
      end

      should "log if the exception message is nil" do
        mock(ExceptionHandling::Sensu).generate_event("some alert", "test context\n")
        ExceptionHandling.ensure_alert('some alert', 'test context') { raise_exception_with_nil_message }
      end
    end

    context "exception timestamp" do
      setup do
        Time.now_override = Time.parse( '1986-5-21 4:17 am UTC' )
      end

      should "include the timestamp when the exception is logged" do
        mock(ExceptionHandling.logger).fatal(/\(Error:517033020\) ArgumentError mooo \(blah\):\n.*exception_handling_test\.rb/)
        b = ExceptionHandling.ensure_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b

        assert_equal 517033020, ExceptionHandling.last_exception_timestamp

        assert_emails 1
        assert_match(/517033020/, ActionMailer::Base.deliveries[-1].body.to_s)
      end
    end

    should "send just one copy of exceptions that don't repeat" do
      ExceptionHandling.log_error(exception_1)
      ExceptionHandling.log_error(exception_2)
      assert_emails 2
      assert_match(/Exception 1/, ActionMailer::Base.deliveries[-2].subject)
      assert_match(/Exception 2/, ActionMailer::Base.deliveries[-1].subject)
    end

    should "not send emails if exception is a warning" do
      ExceptionHandling.log_error(ExceptionHandling::Warning.new("Don't send email"))
      assert_emails 0
    end

    should "not send emails when log_warning is called" do
      ExceptionHandling.log_warning("Don't send email")
      assert_emails 0
    end

    should "log the error if the exception message is nil" do
      ExceptionHandling.log_error(exception_with_nil_message)
      assert_emails(1)
      assert_match(/RuntimeError/, ActionMailer::Base.deliveries.last.subject)
    end

    should "log the error if the exception message is nil and the exception context is a hash" do
      ExceptionHandling.log_error(exception_with_nil_message, "SERVER_NAME" => "exceptional.com")
      assert_emails(1)
      assert_match(/RuntimeError/, ActionMailer::Base.deliveries.last.subject)
    end

    should "only send 5 of a repeated error, but call post hook for every exception" do
      @fail_count = 0
      ExceptionHandling.post_log_error_hook = method(:log_error_callback)
      assert_emails 5 do
        10.times do
          ExceptionHandling.log_error(exception_1)
        end
      end
      assert_equal 10, @fail_count
    end

    should "only send 5 of a repeated error but don't send summary if 6th is different" do
      assert_emails 5 do
        5.times do
          ExceptionHandling.log_error(exception_1)
        end
      end
      assert_emails 1 do
        ExceptionHandling.log_error(exception_2)
      end
    end

    should "send the summary when the error is encountered an hour after the first occurrence" do
      assert_emails 5 do # 5 exceptions, 4 summarized
        9.times do |t|
          ExceptionHandling.log_error(exception_1)
        end
      end
      Time.now_override = 2.hours.from_now
      assert_emails 1 do # 1 summary (4 + 1 = 5) after 2 hours
        ExceptionHandling.log_error(exception_1)
      end
      assert_match(/\[5 SUMMARIZED\]/, ActionMailer::Base.deliveries.last.subject)
      assert_match(/This exception occurred 5 times since/, ActionMailer::Base.deliveries.last.body.to_s)

      assert_emails 0 do # still summarizing...
        7.times do
          ExceptionHandling.log_error(exception_1)
        end
      end

      Time.now_override = 3.hours.from_now

      assert_emails 1 + 2 do # 1 summary and 2 new
        2.times do
          ExceptionHandling.log_error(exception_2)
        end
      end
      assert_match(/\[7 SUMMARIZED\]/, ActionMailer::Base.deliveries[-3].subject)
      assert_match(/This exception occurred 7 times since/, ActionMailer::Base.deliveries[-3].body.to_s)
    end

    should "send the summary if a summary is available, but not sent when another exception comes up" do
      assert_emails 5 do # 5 to start summarizing
        6.times do
          ExceptionHandling.log_error(exception_1)
        end
      end

      assert_emails 1 + 1 do # 1 summary of previous, 1 from new exception
        ExceptionHandling.log_error(exception_2)
      end

      assert_match(/\[1 SUMMARIZED\]/, ActionMailer::Base.deliveries[-2].subject)
      assert_match(/This exception occurred 1 times since/, ActionMailer::Base.deliveries[-2].body.to_s)

      assert_emails 5 do # 5 to start summarizing
        10.times do
          ExceptionHandling.log_error(exception_1)
        end
      end

      assert_emails 0 do # still summarizing
        11.times do
          ExceptionHandling.log_error(exception_1)
        end
      end
    end

    context "Honeybadger integration" do
      context "with Honeybadger not defined" do
        should "not invoke send_exception_to_honeybadger when log_error is executed" do
          dont_allow(ExceptionHandling).send_exception_to_honeybadger
          ExceptionHandling.log_error(exception_1)
        end

        should "not invoke send_exception_to_honeybadger when ensure_safe is executed" do
          dont_allow(ExceptionHandling).send_exception_to_honeybadger
          ExceptionHandling.ensure_safe { raise exception_1 }
        end
      end

      context "with Honeybadger defined" do
        setup do
          stub(ExceptionHandling).honeybadger? { true }
          ExceptionHandling.const_set('Honeybadger', HoneybadgerStub)
        end

        teardown do
          ExceptionHandling.send(:remove_const, 'Honeybadger')
        end

        should "not send_exception_to_honeybadger when log_warning is executed" do
          dont_allow(ExceptionHandling).send_exception_to_honeybadger
          ExceptionHandling.log_warning("This should not go to honeybadger")
        end

        should "not send_exception_to_honeybadger when log_error is called with a Warning" do
          dont_allow(ExceptionHandling).send_exception_to_honeybadger
          ExceptionHandling.log_error(ExceptionHandling::Warning.new("This should not go to honeybadger"))
        end

        should "invoke send_exception_to_honeybadger when log_error is executed" do
          mock.proxy(ExceptionHandling).send_exception_to_honeybadger.with_any_args
          ExceptionHandling.log_error(exception_1)
        end

        should "invoke send_exception_to_honeybadger when log_error_rack is executed" do
          mock.proxy(ExceptionHandling).send_exception_to_honeybadger.with_any_args
          ExceptionHandling.log_error_rack(exception_1, {}, nil)
        end

        should "invoke send_exception_to_honeybadger when ensure_safe is executed" do
          mock.proxy(ExceptionHandling).send_exception_to_honeybadger.with_any_args
          ExceptionHandling.ensure_safe { raise exception_1 }
        end

        should "specify error message as an empty string when notifying honeybadger if exception message is nil" do
          mock(ExceptionHandling::Honeybadger).notify.with_any_args do |args|
            assert_equal "", args[:error_message]
          end
          ExceptionHandling.log_error(exception_with_nil_message)
        end

        should "send error details and relevant context data to Honeybadger" do
          Time.now_override = Time.now
          env = { server: "fe98" }
          parameters = { advertiser_id: 435 }
          session = { username: "jsmith" }
          request_uri = "host/path"
          controller = create_dummy_controller(env, parameters, session, request_uri)
          stub(ExceptionHandling).server_name { "invoca_fe98" }

          exception = StandardError.new("Some BS")
          exception.set_backtrace([
            "test/unit/exception_handling_test.rb:847:in `exception_1'",
            "test/unit/exception_handling_test.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"])
          exception_context = { "SERVER_NAME" => "exceptional.com" }

          honeybadger_data = nil
          mock(ExceptionHandling::Honeybadger).notify.with_any_args do |data|
            honeybadger_data = data
          end
          ExceptionHandling.log_error(exception, exception_context, controller) do |data|
            data[:scm_revision] = "5b24eac37aaa91f5784901e9aabcead36fd9df82"
            data[:user_details] = { username: "jsmith" }
            data[:event_response] = "Event successfully received"
            data[:other_section] = "This should not be included in the response"
          end

          expected_data = {
            error_class: :"Test BS",
            error_message: "Some BS",
            exception: exception,
            context: {
              timestamp: Time.now.to_i,
              error_class: "StandardError",
              server: "invoca_fe98",
              scm_revision: "5b24eac37aaa91f5784901e9aabcead36fd9df82",
              notes: "this is used by a test",
              user_details: { "username" => "jsmith" },
              request: {
                "params" => { "advertiser_id" => 435 },
                "rails_root" => "Rails.root not defined. Is this a test environment?",
                "url" => "host/path" },
              session: {
                "key" => nil,
                "data" => { "username" => "jsmith" } },
              environment: {
                "SERVER_NAME" => "exceptional.com" },
              backtrace: [
                "test/unit/exception_handling_test.rb:847:in `exception_1'",
                "test/unit/exception_handling_test.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"],
              event_response: "Event successfully received"
            }
          }
          assert_equal_with_diff expected_data, honeybadger_data
        end

        should "not send notification to honeybadger when exception description has the flag turned off" do
          filter_list = {
            NoHoneybadger: {
              error: "suppress Honeybadger notification",
              send_to_honeybadger: false
            }
          }
          stub(File).mtime { incrementing_mtime }
          mock(YAML).load_file.with_any_args { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }.at_least(1)

          exception = StandardError.new("suppress Honeybadger notification")
          mock.proxy(ExceptionHandling).send_exception_to_honeybadger.with_any_args.once
          dont_allow(ExceptionHandling::Honeybadger).notify
          ExceptionHandling.log_error(exception)
        end
      end
    end

    class EventResponse
      def to_s
        "message from to_s!"
      end
    end

    should "allow sections to have data with just a to_s method" do
      ExceptionHandling.log_error("This is my RingSwitch example.  Log, don't email!") do |data|
        data.merge!(:event_response => EventResponse.new)
      end
      assert_emails 1
      assert_match(/message from to_s!/, ActionMailer::Base.deliveries.last.body.to_s)
    end
  end

  should "rescue exceptions that happen in log_error" do
    stub(ExceptionHandling).make_exception { raise ArgumentError.new("Bad argument") }
    mock(ExceptionHandling).write_exception_to_log(satisfy { |ex| ex.to_s['Bad argument'] },
                                                   satisfy { |context| context['ExceptionHandling.log_error rescued exception while logging Runtime message'] },
                                                   anything)
    stub($stderr).puts
    ExceptionHandling.log_error(RuntimeError.new("A runtime error"), "Runtime message")
  end

  should "rescue exceptions that happen when log_error yields" do
    mock(ExceptionHandling).write_exception_to_log(satisfy { |ex| ex.to_s['Bad argument'] },
                                                   satisfy { |context| context['Context message'] },
                                                   anything)
    ExceptionHandling.log_error(ArgumentError.new("Bad argument"), "Context message") { |data| raise 'Error!!!' }
  end

  context "Exception Filtering" do
    setup do
      filter_list = { :exception1 => { 'error' => "my error message" },
                      :exception2 => { 'error' => "some other message", :session => "misc data" } }
      stub(YAML).load_file { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }

      # bump modified time up to get the above filter loaded
      stub(File).mtime { incrementing_mtime }
    end

    should "handle case where filter list is not found" do
      stub(YAML).load_file { raise Errno::ENOENT.new("File not found") }

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "My error message is in list" )
      assert_emails 1
    end

    should "log exception and suppress email when exception is on filter list" do
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "My error message is in list" )
      assert_emails 0
    end

    should "allow filtering exception on any text in exception data" do
      filters = { :exception1 => { :session => "data: my extra session data" } }
      stub(YAML).load_file { ActiveSupport::HashWithIndifferentAccess.new(filters) }

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "No match here" ) do |data|
        data[:session] = {
            :key         => "@session_id",
            :data        => "my extra session data"
          }
      end
      assert_emails 0

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "No match here" ) do |data|
        data[:session] = {
            :key         => "@session_id",
            :data        => "my extra session <no match!> data"
          }
      end
      assert_emails 1, ActionMailer::Base.deliveries.*.body.*.inspect
    end

    should "reload filter list on the next exception if file was modified" do
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1

      filter_list = { :exception1 => { 'error' => "Error message is not in list" } }
      stub(YAML).load_file { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }
      stub(File).mtime { incrementing_mtime }

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 0, ActionMailer::Base.deliveries.*.body.*.inspect
    end

    should "not consider filter if both error message and body do not match" do
      # error message matches, but not full text
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "some other message" )
      assert_emails 1, ActionMailer::Base.deliveries.*.body.*.inspect

      # now both match
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "some other message" ) do |data|
        data[:session] = {:some_random_key => "misc data"}
      end
      assert_emails 0, ActionMailer::Base.deliveries.*.body.*.inspect
    end

    should "skip environment keys not on whitelist" do
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "some message" ) do |data|
        data[:environment] = { :SERVER_PROTOCOL => "HTTP/1.0", :RAILS_SECRETS_YML_CONTENTS => 'password: VERY_SECRET_PASSWORD' }
      end
      assert_emails 1, ActionMailer::Base.deliveries.*.body.*.inspect
      mail = ActionMailer::Base.deliveries.last
      assert_nil mail.body.to_s["RAILS_SECRETS_YML_CONTENTS"], mail.body.to_s # this is not on whitelist
      assert     mail.body.to_s["SERVER_PROTOCOL: HTTP/1.0" ], mail.body.to_s # this is
    end

    should "omit environment defaults" do
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "some message" ) do |data|
        data[:environment] = {:SERVER_PORT => '80', :SERVER_PROTOCOL => "HTTP/1.0"}
      end
      assert_emails 1, ActionMailer::Base.deliveries.*.body.*.inspect
      mail = ActionMailer::Base.deliveries.last
      assert_nil mail.body.to_s["SERVER_PORT"              ], mail.body.to_s # this was default
      assert     mail.body.to_s["SERVER_PROTOCOL: HTTP/1.0"], mail.body.to_s # this was not
    end

    should "reject the filter file if any contain all empty regexes" do
      filter_list = { :exception1 => { 'error' => "", :session => "" },
                      :exception2 => { 'error' => "is not in list", :session => "" } }
      stub(YAML).load_file { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }
      stub(File).mtime { incrementing_mtime }

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1, ActionMailer::Base.deliveries.*.inspect
    end

    context "Exception Handling Mailer" do
      should "create email" do
        ExceptionHandling.log_error(exception_1) do |data|
          data[:request] = { :params => {:id => 10993}, :url => "www.ringrevenue.com" }
          data[:session] = { :key => "DECAFE" }
        end
        assert_emails 1, ActionMailer::Base.deliveries.*.inspect
        assert mail = ActionMailer::Base.deliveries.last
        assert_equal ['exceptions@example.com'], mail.to
        assert_equal ['server@example.com'].to_s, mail.from.to_s
        assert_match /Exception 1/, mail.to_s
        assert_match /key: DECAFE/, mail.to_s
        assert_match /id: 10993/, mail.to_s
      end

      EXPECTED_SMTP_HASH =
          {
              :host   => '127.0.0.1',
              :domain => 'localhost.localdomain',
              :from   => 'server@example.com',
              :to     => 'exceptions@example.com'
          }

      [[true, false], [true, true]].each do |em_flag, synchrony_flag|
        context "eventmachine_safe = #{em_flag} && eventmachine_synchrony = #{synchrony_flag}" do
          setup do
            ExceptionHandling.eventmachine_safe       = em_flag
            ExceptionHandling.eventmachine_synchrony  = synchrony_flag
            EventMachineStub.block = nil
            set_test_const('EventMachine', EventMachineStub)
            set_test_const('EventMachine::Protocols', Module.new)
            set_test_const('EventMachine::DNS', Module.new)
            set_test_const('EventMachine::DNS::Resolver', DNSResolvStub)
          end

          teardown do
            ExceptionHandling.eventmachine_safe       = false
            ExceptionHandling.eventmachine_synchrony  = false
          end

          should "schedule EventMachine STMP when EventMachine defined" do
            set_test_const('EventMachine::Protocols::SmtpClient', SmtpClientStub)

            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            assert DNSResolvStub.callback_block
            DNSResolvStub.callback_block.call ['127.0.0.1']
            assert_equal_with_diff EXPECTED_SMTP_HASH, (SmtpClientStub.send_hash & EXPECTED_SMTP_HASH.keys).map_hash { |k,v| v.to_s }, SmtpClientStub.send_hash.inspect
            assert_equal((synchrony_flag ? :asend : :send), SmtpClientStub.last_method)
            assert_match(/Exception 1/, SmtpClientStub.send_hash[:content])
            assert_emails 0, ActionMailer::Base.deliveries.*.to_s
          end

          should "pass the content as a proper rfc 2822 message" do
            set_test_const('EventMachine::Protocols::SmtpClient', SmtpClientStub)
            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            assert DNSResolvStub.callback_block
            DNSResolvStub.callback_block.call ['127.0.0.1']
            assert content = SmtpClientStub.send_hash[:content]
            assert_match(/Content-Transfer-Encoding: 7bit/, content)
            assert_match(/\r\n\.\r\n\z/, content)
          end

          should "log fatal on EventMachine STMP errback" do
            assert_emails 0, ActionMailer::Base.deliveries.*.to_s
            set_test_const('EventMachine::Protocols::SmtpClient', SmtpClientErrbackStub)
            mock(ExceptionHandling.logger).fatal(/Exception 1/)
            mock(ExceptionHandling.logger).fatal(/Failed to email by SMTP: "credential mismatch"/)

            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            assert DNSResolvStub.callback_block
            DNSResolvStub.callback_block.call(['127.0.0.1'])
            SmtpClientErrbackStub.block.call("credential mismatch")
            assert_equal_with_diff EXPECTED_SMTP_HASH, (SmtpClientErrbackStub.send_hash & EXPECTED_SMTP_HASH.keys).map_hash { |k,v| v.to_s }, SmtpClientErrbackStub.send_hash.inspect
            #assert_emails 0, ActionMailer::Base.deliveries.*.to_s
          end

          should "log fatal on EventMachine dns resolver errback" do
            assert_emails 0, ActionMailer::Base.deliveries.*.to_s
            mock(ExceptionHandling.logger).fatal(/Exception 1/)
            mock(ExceptionHandling.logger).fatal(/Failed to resolv DNS for localhost: "softlayer sucks"/)

            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            DNSResolvStub.errback_block.call("softlayer sucks")
          end
        end
      end
    end

    should "truncate email subject" do
      ActionMailer::Base.deliveries.clear
      text = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM".split('').join("123456789")
      begin
        raise text
      rescue => ex
        ExceptionHandling.log_error( ex )
      end
      assert_emails 1, ActionMailer::Base.deliveries.*.inspect
      mail = ActionMailer::Base.deliveries.last
      subject = "#{ExceptionHandling.email_environment} exception: RuntimeError: " + text
      assert_equal subject[0,300], mail.subject
    end
  end

  context "Exception mapping" do
    setup do
      @data = {
        :environment=>{
          'HTTP_HOST' => "localhost",
          'HTTP_REFERER' => "http://localhost/action/controller/instance",
        },
        :session=>{
          :data=>{
            :affiliate_id=> defined?(Affiliate) ? Affiliate.first.id : '1',
            :edit_mode=> true,
            :advertiser_id=> defined?(Advertiser) ? Advertiser.first.id : '1',
            :username_id=> defined?(Username) ? Username.first.id : '1',
            :user_id=> defined?(User) ? User.first.id : '1',
            :flash=>{},
            :impersonated_organization_pk=> 'Advertiser_1'
          }
        },
        :request=>{},
        :backtrace=>["[GEM_ROOT]/gems/actionpack-2.1.0/lib/action_controller/filters.rb:580:in `call_filters'", "[GEM_ROOT]/gems/actionpack-2.1.0/lib/action_controller/filters.rb:601:in `run_before_filters'"],
        :api_key=>"none",
        :error_class=>"StandardError",
        :error=>'Some error message'
      }
    end

    should "clean backtraces" do
      begin
        raise "test exception"
      rescue => ex
        backtrace = ex.backtrace
      end
      result = ExceptionHandling.send(:clean_backtrace, ex).to_s
      assert_not_equal result, backtrace
    end

    should "return entire backtrace if cleaned is emtpy" do
      begin
        backtrace = ["/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activerecord/lib/active_record/relation/finder_methods.rb:312:in `find_with_ids'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activerecord/lib/active_record/relation/finder_methods.rb:107:in `find'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activerecord/lib/active_record/querying.rb:5:in `__send__'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activerecord/lib/active_record/querying.rb:5:in `find'",
                     "/Library/Ruby/Gems/1.8/gems/shoulda-context-1.0.2/lib/shoulda/context/context.rb:398:in `call'",
                     "/Library/Ruby/Gems/1.8/gems/shoulda-context-1.0.2/lib/shoulda/context/context.rb:398:in `test: Exception mapping should return entire backtrace if cleaned is emtpy. '",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/testing/setup_and_teardown.rb:72:in `__send__'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/testing/setup_and_teardown.rb:72:in `run'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:447:in `_run__1913317170__setup__4__callbacks'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:405:in `send'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:405:in `__run_callback'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:385:in `_run_setup_callbacks'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:81:in `send'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/callbacks.rb:81:in `run_callbacks'",
                     "/Users/peter/ringrevenue/web/vendor/rails-3.2.12/activesupport/lib/active_support/testing/setup_and_teardown.rb:70:in `run'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:34:in `run'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `each'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/testsuite.rb:33:in `run'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnermediator.rb:46:in `old_run_suite'",
                     "(eval):12:in `run_suite'",
                     "/Applications/RubyMine.app/rb/testing/patch/testunit/test/unit/ui/teamcity/testrunner.rb:93:in `send'",
                     "/Applications/RubyMine.app/rb/testing/patch/testunit/test/unit/ui/teamcity/testrunner.rb:93:in `start_mediator'",
                     "/Applications/RubyMine.app/rb/testing/patch/testunit/test/unit/ui/teamcity/testrunner.rb:81:in `start'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/ui/testrunnerutilities.rb:29:in `run'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit/autorunner.rb:12:in `run'",
                     "/System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/test/unit.rb:279",
                     "-e:1"]

        module ::Rails
          class BacktraceCleaner
            def clean(_backtrace)
              []
            end
          end
        end

        mock(Rails).backtrace_cleaner { Rails::BacktraceCleaner.new }

        ex = Exception.new
        ex.set_backtrace(backtrace)
        result = ExceptionHandling.send(:clean_backtrace, ex)
        assert_equal backtrace, result
      ensure
        Object.send(:remove_const, :Rails)
      end
    end
  end

  context "log_perodically" do
    setup do
      Time.now_override = Time.now # Freeze time
      ExceptionHandling.logger.clear
    end

    teardown do
      Time.now_override = nil
    end

    should "log immediately when we are expected to log" do
      logger_stub = ExceptionHandling.logger

      ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will be written")
      assert_equal 1, logger_stub.logged.size

      Time.now_override = Time.now + 5.minutes
      ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will not be written")
      assert_equal 1, logger_stub.logged.size

      ExceptionHandling.log_periodically(:test_another_periodic_exception, 30.minutes, "this will be written")
      assert_equal 2, logger_stub.logged.size

      Time.now_override = Time.now + 26.minutes

      ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will be written")
      assert_equal 3, logger_stub.logged.size
    end
  end

  private

  def incrementing_mtime
    @mtime ||= Time.now
    @mtime += 1.day
  end

  def exception_1
    @ex1 ||=
      begin
        raise StandardError, "Exception 1"
      rescue => ex
        ex
      end
  end

  def exception_2
    @ex2 ||=
      begin
        raise StandardError, "Exception 2"
      rescue => ex
        ex
      end
  end
end
