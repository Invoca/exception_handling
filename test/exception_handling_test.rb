require './test/test_helper'
require 'minitest/autorun'
require 'exception_handling'

ExceptionHandling.email_environment     = 'test'
ExceptionHandling.sender_address        = 'server@example.com'
ExceptionHandling.exception_recipients  = 'exceptions@example.com'
ExceptionHandling.server_name           = 'server'

class ExceptionHandlingTest < ActiveSupport::TestCase
  class LoggerStub
    attr_accessor :logged

    def initialize
      clear
    end

    def info(message)
      logged << message
    end

    def warn(message)
      logged << message
    end

    def fatal(message)
      logged << message
    end

    def clear
      @logged = []
    end
  end


  ExceptionHandling.logger = LoggerStub.new

  def dont_stub_log_error
    true
  end

  class TestController
    class Request
      attr_accessor :parameters, :protocol, :host, :request_uri, :env, :session_options
      def initialize
        @parameters  = {:id => "1"}
        @protocol    = 'http'
        @host        = 'localhost'
        @request_uri = "/fun/testing.html?foo=bar"
        @env         = {:HOST => "local"}
        @session_options = { :id => '93951506217301' }
      end
    end

    attr_accessor :request, :session
    class << self
      attr_accessor :around_filter_method
    end

    def initialize
      @request = Request.new
      @session_id = "ZKL95"
      @session =
          if defined?(Username)
            {
              :login_count => 22,
              :username_id => Username.first.id,
              :user_id     => User.first.id,
            }
          else
            { }
          end
    end

    def simulate_around_filter( &block )
      set_current_controller( &block )
    end

    def controller_name
      "TestController"
    end

    def action_name
      "test_action"
    end

    def self.around_filter( method )
      TestController.around_filter_method = method
    end

    def complete_request_uri
      "#{@request.protocol}#{@request.host}#{@request.request_uri}"
    end

    include ExceptionHandling::Methods
  end

if defined?(Rails)
  class TestAdvertiser < Advertiser
    def test_log_error( ex, message=nil )
      log_error(ex, message)
    end

    def test_ensure_escalation(summary)
      ensure_escalation(summary) do
        yield
      end
    end

    def test_log_warning( message )
      log_warning(message)
    end

    def test_ensure_safe(message="",&blk)
      ensure_safe(message,&blk)
    end

    def self.task_exception exception
      @@task_exception = exception
    end
  end
end

  module EventMachineStub
    class << self
      attr_accessor :block

      def schedule(&block)
        @block = block
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

  context "Exception Handling" do
    setup do
      ExceptionHandling.send(:clear_exception_summary)
    end

    context "exception filter parsing and loading" do
      should "happen without an error" do
        File.stubs(:mtime).returns( incrementing_mtime )
        exception_filters = ExceptionHandling.send( :exception_filters )
        assert( exception_filters.is_a?( ExceptionHandling::ExceptionFilters ) )
        assert_nothing_raised "Loading the exception filter should not raise" do
          exception_filters.send :load_file
        end
        assert !exception_filters.filtered?( "Scott says unlikely to ever match" )
      end
    end

    context "ExceptionHandling.ensure_safe" do
      should "log an exception if an exception is raised." do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        ExceptionHandling.ensure_safe { raise ArgumentError.new("blah") }
      end

      should "should not log an exception if an exception is not raised." do
        ExceptionHandling.logger.expects(:fatal).never
        ExceptionHandling.ensure_safe { ; }
      end

      should "return its value if used during an assignment" do
        ExceptionHandling.logger.expects(:fatal).never
        b = ExceptionHandling.ensure_safe { 5 }
        assert_equal 5, b
      end

      should "return nil if an exception is raised during an assignment" do
        ExceptionHandling.logger.expects(:fatal).returns(nil)
        b = ExceptionHandling.ensure_safe { raise ArgumentError.new("blah") }
        assert_equal nil, b
      end

      should "allow a message to be appended to the error when logged." do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo \(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        b = ExceptionHandling.ensure_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "only rescue StandardError and descendents" do
        assert_raise(Exception) { ExceptionHandling.ensure_safe("mooo") { raise Exception } }

        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo \(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        b = ExceptionHandling.ensure_safe("mooo") { raise StandardError.new("blah") }
        assert_nil b
      end
    end

    context "ExceptionHandling.ensure_completely_safe" do
      should "log an exception if an exception is raised." do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        ExceptionHandling.ensure_completely_safe { raise ArgumentError.new("blah") }
      end

      should "should not log an exception if an exception is not raised." do
        ExceptionHandling.logger.expects(:fatal).never
        ExceptionHandling.ensure_completely_safe { ; }
      end

      should "return its value if used during an assignment" do
        ExceptionHandling.logger.expects(:fatal).never
        b = ExceptionHandling.ensure_completely_safe { 5 }
        assert_equal 5, b
      end

      should "return nil if an exception is raised during an assignment" do
        ExceptionHandling.logger.expects(:fatal).returns(nil)
        b = ExceptionHandling.ensure_completely_safe { raise ArgumentError.new("blah") }
        assert_equal nil, b
      end

      should "allow a message to be appended to the error when logged." do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo \(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        b = ExceptionHandling.ensure_completely_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b
      end

      should "rescue any instance or child of Exception" do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
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
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        ExceptionHandling.ensure_escalation( "Favorite Feature") { raise ArgumentError.new("blah") }
        assert_equal 2, ActionMailer::Base.deliveries.count
        email = ActionMailer::Base.deliveries.last
        assert_equal 'test Escalation: Favorite Feature', email.subject
        assert_match 'ArgumentError: blah', email.body.to_s
        assert_match ExceptionHandling.last_exception_timestamp.to_s, email.body.to_s
      end

      should "should not escalate if an exception is not raised." do
        assert_equal 0, ActionMailer::Base.deliveries.count
        ExceptionHandling.logger.expects(:fatal).never
        ExceptionHandling.ensure_escalation('Ignored') { ; }
        assert_equal 0, ActionMailer::Base.deliveries.count
      end

      should "log if the escalation email can not be sent" do
        Mail::Message.any_instance.expects(:deliver).times(2).returns(nil).then.raises(RuntimeError.new "Delivery Error")
        exception_count = 0
        exception_regexs = [/first_test_exception/, /safe_email_deliver .*Delivery Error/]

        $stderr.stubs(:puts)
        ExceptionHandling.logger.expects(:fatal).times(2).with { |ex| ex =~ exception_regexs[exception_count] or raise "Unexpected [#{exception_count}]: #{ex.inspect}"; exception_count += 1; true }
        ExceptionHandling.ensure_escalation("Not Used") { raise ArgumentError.new("first_test_exception") }
        #assert_equal 0, ActionMailer::Base.deliveries.count
      end
    end

    context "exception timestamp" do
      setup do
        Time.now_override = Time.parse( '1986-5-21 4:17 am UTC' )
      end

      should "include the timestamp when the exception is logged" do
        ExceptionHandling.logger.expects(:fatal).with { |ex| ex =~ /\(Error:517033020\) ArgumentError mooo \(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
        b = ExceptionHandling.ensure_safe("mooo") { raise ArgumentError.new("blah") }
        assert_nil b

        assert_equal 517033020, ExceptionHandling.last_exception_timestamp

        assert_emails 1
        assert_match /517033020/, ActionMailer::Base.deliveries[-1].body.to_s
      end
    end

  if defined?(LogErrorStub)
    context "while running tests" do
      setup do
        stub_log_error
      end

      should "raise an error when log_error and log_warning are called" do
        begin
          ExceptionHandling.log_error("Something happened")
          flunk
        rescue LogErrorStub::UnexpectedExceptionLogged => ex
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
        expects_exception /StandardError: This is a test error/
        expects_exception /IgnoredError: This should be ignored/
        ExceptionHandling.log_error("This is a test error")
        begin
          raise IgnoredError, "This should be ignored"
        rescue IgnoredError => ex
          ExceptionHandling.log_error(ex)
        end
      end

      should "expect exception twice if declared twice" do
        expects_exception /StandardError: ERROR: I love lamp/
        expects_exception /StandardError: ERROR: I love lamp/
        ExceptionHandling.log_error("ERROR: I love lamp")
        ExceptionHandling.log_error("ERROR: I love lamp")
      end
    end
  end

    should "send just one copy of exceptions that don't repeat" do
      ExceptionHandling.log_error(exception_1)
      ExceptionHandling.log_error(exception_2)
      assert_emails 2
      assert_match /Exception 1/, ActionMailer::Base.deliveries[-2].subject
      assert_match /Exception 2/, ActionMailer::Base.deliveries[-1].subject
    end

    should "only send 5 of a repeated error" do
      assert_emails 5 do
        10.times do
          ExceptionHandling.log_error(exception_1)
        end
      end
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
      assert_match /\[5 SUMMARIZED\]/, ActionMailer::Base.deliveries.last.subject
      assert_match /This exception occurred 5 times since/, ActionMailer::Base.deliveries.last.body.to_s

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
      assert_match /\[7 SUMMARIZED\]/, ActionMailer::Base.deliveries[-3].subject
      assert_match /This exception occurred 7 times since/, ActionMailer::Base.deliveries[-3].body.to_s
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

      assert_match /\[1 SUMMARIZED\]/, ActionMailer::Base.deliveries[-2].subject
      assert_match /This exception occurred 1 times since/, ActionMailer::Base.deliveries[-2].body.to_s

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
      assert_match /message from to_s!/, ActionMailer::Base.deliveries.last.body.to_s
    end
  end

  should "rescue exceptions that happen in log_error" do
    ExceptionHandling.stubs(:make_exception).raises(ArgumentError.new("Bad argument"))
    ExceptionHandling.expects(:write_exception_to_log).with do |ex, context, timestamp|
      ex.to_s['Bad argument'] or raise "Unexpected ex #{ex.class} - #{ex}"
      context['ExceptionHandling.log_error rescued exception while logging Runtime message'] or raise "Unexpected context #{context}"
      true
    end
    $stderr.stubs(:puts)
    ExceptionHandling.log_error(RuntimeError.new("A runtime error"), "Runtime message")
  end

  should "rescue exceptions that happen when log_error yields" do
    ExceptionHandling.expects(:write_exception_to_log).with do |ex, context, timestamp|
      ex.to_s['Bad argument'] or raise "=================================================\nUnexpected ex #{ex.class} - #{ex}\n#{ex.backtrace.join("\n")}\n=============================================\n"
      context['Context message'] or raise "Unexpected context #{context}"
      true
    end
    ExceptionHandling.log_error(ArgumentError.new("Bad argument"), "Context message") { |data| raise 'Error!!!' }
  end

  context "Exception Filtering" do
    setup do
      filter_list = { :exception1 => { :error => "my error message" },
                      :exception2 => { :error => "some other message", :session => "misc data" } }
      YAML.stubs(:load_file).returns( ActiveSupport::HashWithIndifferentAccess.new( filter_list ) )

      # bump modified time up to get the above filter loaded
      File.stubs(:mtime).returns( incrementing_mtime )
    end

    should "handle case where filter list is not found" do
      YAML.stubs(:load_file).raises( Errno::ENOENT.new( "File not found" ) )

      ExceptionHandling.log_error( "My error message is in list" )
      assert_emails 1
    end

    should "log exception and suppress email when exception is on filter list" do
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "My error message is in list" )
      assert_emails 0
    end

    should "allow filtering exception on any text in exception data" do
      filters = { :exception1 => { :session => "^data: my extra session data" } }
      YAML.stubs(:load_file).returns( ActiveSupport::HashWithIndifferentAccess.new( filters ) )

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
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
    end

    should "reload filter list on the next exception if file was modified" do
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1

      filter_list = { :exception1 => { :error => "Error message is not in list" } }
      YAML.stubs(:load_file).returns( ActiveSupport::HashWithIndifferentAccess.new( filter_list ) )
      File.stubs(:mtime).returns( incrementing_mtime )

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 0, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
    end

    should "not consider filter if both error message and body do not match" do
      # error message matches, but not full text
      ExceptionHandling.log_error( "some other message" )
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }

      # now both match
      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "some other message" ) do |data|
        data[:session] = {:some_random_key => "misc data"}
      end
      assert_emails 0, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
    end

    should "skip environment keys not on whitelist" do
      ExceptionHandling.log_error( "some message" ) do |data|
        data[:environment] = { :SERVER_PROTOCOL => "HTTP/1.0", :RAILS_SECRETS_YML_CONTENTS => 'password: VERY_SECRET_PASSWORD' }
      end
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
      mail = ActionMailer::Base.deliveries.last
      assert_nil mail.body.to_s["RAILS_SECRETS_YML_CONTENTS"], mail.body.to_s # this is not on whitelist
      assert     mail.body.to_s["SERVER_PROTOCOL: HTTP/1.0" ], mail.body.to_s # this is
    end

    should "omit environment defaults" do
      ExceptionHandling.log_error( "some message" ) do |data|
        data[:environment] = {:SERVER_PORT => '80', :SERVER_PROTOCOL => "HTTP/1.0"}
      end
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
      mail = ActionMailer::Base.deliveries.last
      assert_nil mail.body.to_s["SERVER_PORT"              ], mail.body.to_s # this was default
      assert     mail.body.to_s["SERVER_PROTOCOL: HTTP/1.0"], mail.body.to_s # this was not
    end

    should "reject the filter file if any contain all empty regexes" do
      filter_list = { :exception1 => { :error => "", :session => "" },
                      :exception2 => { :error => "is not in list", :session => "" } }
      YAML.stubs(:load_file).returns( ActiveSupport::HashWithIndifferentAccess.new( filter_list ) )
      File.stubs(:mtime).returns( incrementing_mtime )

      ActionMailer::Base.deliveries.clear
      ExceptionHandling.log_error( "Error message is not in list" )
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
    end

    context "Exception Handling Mailer" do
      should "create email" do
        ExceptionHandling.log_error(exception_1) do |data|
          data[:request] = { :params => {:id => 10993}, :url => "www.ringrevenue.com" }
          data[:session] = { :key => "DECAFE" }
        end
        assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
        assert mail = ActionMailer::Base.deliveries.last
        assert_equal ['exceptions@example.com'], mail.to
        assert_equal ['server@example.com'].to_s, mail.from.to_s
        assert_match /Exception 1/, mail.to_s
        assert_match /key: DECAFE/, mail.to_s
        assert_match /id: 10993/, mail.to_s
      end

      EXPECTED_SMTP_HASH =
          {
              :host   => 'localhost',
              :domain => 'localhost.localdomain',
              :from   => 'server@example.com',
              :to     => 'exceptions@example.com'
          }

      [true, :Synchrony].each do |synchrony_flag|
        context "EVENTMACHINE_EXCEPTION_HANDLING = #{synchrony_flag}" do
          setup do
            set_test_const('EVENTMACHINE_EXCEPTION_HANDLING', synchrony_flag)
            EventMachineStub.block = nil
            set_test_const('EventMachine', EventMachineStub)
            set_test_const('EventMachine::Protocols', Module.new)
          end

          should "schedule EventMachine STMP when EventMachine defined" do
            set_test_const('EventMachine::Protocols::SmtpClient', SmtpClientStub)

            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            EXPECTED_SMTP_HASH.map { |key, value| assert_equal value, SmtpClientStub.send_hash[key].to_s, SmtpClientStub.send_hash.inspect }
            assert_equal (synchrony_flag == :Synchrony ? :asend : :send), SmtpClientStub.last_method
            assert_match /Exception 1/, SmtpClientStub.send_hash[:body]
            assert_emails 0, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
          end

          should "log fatal on EventMachine STMP errback" do
            set_test_const('EventMachine::Protocols::SmtpClient', SmtpClientErrbackStub)
            ExceptionHandling.logger.expects(:fatal).twice.with do |message|
              assert message =~ /Failed to email by SMTP: "credential mismatch"/ || message =~ /Exception 1/, message
              true
            end
            ExceptionHandling.log_error(exception_1)
            assert EventMachineStub.block
            EventMachineStub.block.call
            SmtpClientErrbackStub.block.call("credential mismatch")
            EXPECTED_SMTP_HASH.map { |key, value| assert_equal value, SmtpClientErrbackStub.send_hash[key].to_s, SmtpClientErrbackStub.send_hash.inspect }
            assert_emails 0, ActionMailer::Base.deliveries.map { |m| m.body.inspect }
          end
        end
      end
    end

    should "truncate email subject" do
      text = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM".split('').join("123456789")
      begin
        raise text
      rescue => ex
        ExceptionHandling.log_error( ex )
      end
      assert_emails 1, ActionMailer::Base.deliveries.map { |m| m.inspect }
      mail = ActionMailer::Base.deliveries.last
      subject = "test exception: RuntimeError: " + text
      assert_equal subject[0,300], mail.subject
    end
  end

  if defined?(Rails)
    context "ExceptionHandling.Methods" do
      setup do
        @controller = TestController.new
      end

      teardown do
        Time.now_override = nil
      end

      should "set the around filter" do
        assert_equal :set_current_controller, TestController.around_filter_method
        assert_nil ExceptionHandling.current_controller
        @controller.simulate_around_filter( ) do
          assert_equal @controller, ExceptionHandling.current_controller
        end
        assert_nil ExceptionHandling.current_controller
      end

      should "use the current controller when included in a Model" do
        ActiveRecord::Base.logger.expects(:fatal).with { |ex| ex =~ /blah/ }
        @controller.simulate_around_filter( ) do
          a = TestAdvertiser.new :name => 'Joe Ads'
          a.test_log_error( ArgumentError.new("blah") )
          mail = ActionMailer::Base.deliveries.last
          assert_equal EXCEPTION_HANDLING_MAILER_RECIPIENTS, mail.to
          assert_match( @controller.request.request_uri, mail.body.to_s )
          assert_match( Username.first.username.to_s, mail.body.to_s )
        end
      end

      should "use the current_controller when available" do
        ActiveRecord::Base.logger.expects(:fatal).with( ) { |ex| ex =~ /blah/ }
        @controller.simulate_around_filter do
          ExceptionHandling.log_error( ArgumentError.new("blah") )
          mail = ActionMailer::Base.deliveries.last
         assert_equal EXCEPTION_HANDLING_MAILER_RECIPIENTS, mail.to
         assert_match( @controller.request.request_uri, mail.body )
         assert_match( Username.first.username.to_s, mail.body )
          mail = ActionMailer::Base.deliveries.last
         assert_equal EXCEPTION_HANDLING_MAILER_RECIPIENTS, mail.to
         assert_match( @controller.request.request_uri, mail.body.to_s )
         assert_match( Username.first.username.to_s, mail.body.to_s )
          assert mail = ActionMailer::Base.deliveries.last
          assert_equal EXCEPTION_HANDLING_MAILER_RECIPIENTS, mail.to
          assert_match( @controller.request.request_uri, mail.body.to_s )
          assert_match( Username.first.username.to_s, mail.body.to_s )
        end
      end

      should "report long running controller action" do
        # If stubbing this causes problems, retreat.
        Rails.expects(:env).returns('production')
        ExceptionHandling.logger.expects(:fatal).with { |ex| ex =~ /Long controller action detected in TestController::test_action/ or raise "Unexpected: #{ex.inspect}"}
        @controller.simulate_around_filter( ) do
          Time.now_override = 1.hour.from_now
        end
      end
    end

    context "a model object" do
      setup do
        @a = TestAdvertiser.new :name => 'Joe Ads'
      end

      context "with an argument error" do
        setup do
          begin
            raise ArgumentError.new("blah");
          rescue => ex
            @argument_error = ex
          end
        end

        context "log_error on a model" do
          should "log errors" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
            @a.test_log_error( @argument_error )
          end

          should "log errors from strings" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling\.rb/ or raise "Unexpected: #{ex.inspect}" }
            @a.test_log_error( "blah" )
          end

          should "log errors with strings" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo.* \(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
            @a.test_log_error( @argument_error, "mooo" )
          end
        end

        context "ensure_escalation on a model" do
          should "work" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
            @a.test_ensure_escalation 'Favorite Feature' do
              raise @argument_error
            end
            assert_equal 2, ActionMailer::Base.deliveries.count
            email = ActionMailer::Base.deliveries.last
            assert_equal 'development-local Escalation: Favorite Feature', email.subject
            assert_match 'ArgumentError: blah', email.body.to_s
          end
        end

        context "ExceptionHandling.log_error" do
          should "log errors" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
            ExceptionHandling.log_error( @argument_error )
          end

          should "log errors from strings" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling\.rb/ or raise "Unexpected: #{ex.inspect}" }
            ExceptionHandling.log_error( "blah" )
          end

          should "log errors with strings" do
            ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo.*\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
            ExceptionHandling.log_error( @argument_error, "mooo" )
          end
        end
      end

      should "log warnings" do
        ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /blah/ }
        @a.test_log_warning("blah")
      end

      context "ensure_safe on the model" do
        should "log an exception if an exception is raised." do
          ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
          @a.test_ensure_safe { raise ArgumentError.new("blah") }
        end

        should "should not log an exception if an exception is not raised." do
          ExceptionHandling.logger.expects(:fatal).never
          @a.test_ensure_safe { ; }
        end

        should "return its value if used during an assignment" do
          ExceptionHandling.logger.expects(:fatal).never
          b = @a.test_ensure_safe { 5 }
          assert_equal 5, b
        end

        should "return nil if an exception is raised during an assignment" do
          ExceptionHandling.logger.expects(:fatal).returns(nil)
          b = @a.test_ensure_safe { raise ArgumentError.new("blah") }
          assert_nil b
        end

        should "allow a message to be appended to the error when logged." do
          ExceptionHandling.logger.expects(:fatal).with( ) { |ex| ex =~ /mooo.*\(blah\):\n.*exception_handling_test\.rb/ or raise "Unexpected: #{ex.inspect}" }
          b = @a.test_ensure_safe("mooo") { raise ArgumentError.new("blah") }
          assert_nil b
        end
      end
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

    should "clean params" do
      p = {'password' => 'apple', 'username' => 'sam' }
      ExceptionHandling.send( :clean_params, p )
      assert_equal "[FILTERED]", p['password']
      assert_equal 'sam', p['username']
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

  context "Errplane" do
    module ErrplaneStub
    end

    setup do
      set_test_const('Errplane', ErrplaneStub)
    end

    should "forward exceptions" do
      ex = data = nil
      Errplane.expects(:transmit).with do |ex_, data_|
        ex, data = ex_, data_
        true
      end

      ExceptionHandling.log_error(exception_1, "context")

      assert_equal exception_1, ex, ex.inspect
      custom_data = data[:custom_data]
      custom_data["error"].include?("context") or raise "Wrong custom_data #{custom_data["error"].inspect}"
    end

    should "not forward warnings" do
      never = true
      Errplane.stubs(:transmit).with do
        never = false
        true
      end

      ExceptionHandling.log_warning("warning message")

      assert never, "transmit should not have been called"
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
