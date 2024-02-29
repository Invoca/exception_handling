# frozen_string_literal: true

# some useful test objects

module ExceptionHandling
  module Testing
    class ControllerStubBase

      class Request
        attr_accessor :parameters, :protocol, :host, :request_uri, :env, :session_options

        def initialize
          @parameters  = { id: "1" }
          @protocol    = 'http'
          @host        = 'localhost'
          @request_uri = "/fun/testing.html?foo=bar"
          @env         = { HOST: "local" }
          @session_options = { id: '93951506217301' }
        end
      end

      attr_accessor :request, :session

      class << self
        attr_accessor :around_filter_method

        def around_filter(method)
          self.around_filter_method = method
        end
      end

      def initialize
        @request = Request.new
        @session_id = "ZKL95"
        @session =
          if defined?(Username)
            {
              login_count: 22,
              username_id: Username.first.id,
              user_id: User.first.id,
            }
          else
            {}
          end
      end

      def action_name
        "test_action"
      end

      def complete_request_uri
        "#{@request.protocol}#{@request.host}#{@request.request_uri}"
      end
    end

    class LoggingMethodsControllerStub < ControllerStubBase
      include ExceptionHandling::LoggingMethods

      def controller_name
        "LoggingMethodsControllerStub"
      end
    end
  end
end
