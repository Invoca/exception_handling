require File.expand_path('../../../test_helper',  __FILE__)

class MethodsTest < ActiveSupport::TestCase

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

  context "ExceptionHandling.Methods" do
    setup do
      @controller = TestController.new
      ExceptionHandling.stub_handler = nil
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
      mock(ExceptionHandling).log_error(/Long controller action detected in TestController::test_action/, anything, anything)
      @controller.simulate_around_filter( ) do
        Time.now_override = 1.day.from_now
      end
    end
  end

end
