# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)
require_test_helper 'controller_helpers'
require_test_helper 'exception_helpers'

module ExceptionHandling
  class ExceptionInfoTest < ActiveSupport::TestCase
    include ControllerHelpers
    include ExceptionHelpers

    context "initialize" do
      setup do
        @exception = StandardError.new("something went wrong")
        @timestamp = Time.now
        @controller = Object.new
      end

      context "controller_from_context" do
        should "extract controller from context when not specified explicitly" do
          exception_context = {
            "action_controller.instance" => @controller
          }
          exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp)
          assert_equal @controller, exception_info.controller
        end

        should "prefer the explicit controller over the one from context" do
          exception_context = {
            "action_controller.instance" => Object.new
          }
          exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp, controller: @controller)
          assert_equal @controller, exception_info.controller
          assert_not_equal exception_context["action_controller.instance"], exception_info.controller
        end

        should "leave controller unset when not included in the context hash" do
          exception_info = ExceptionInfo.new(@exception, {}, @timestamp)
          assert_nil exception_info.controller
        end

        should "leave controller unset when context is not in hash format" do
          exception_info = ExceptionInfo.new(@exception, "string context", @timestamp)
          assert_nil exception_info.controller
        end
      end
    end

    context "data" do
      setup do
        @exception = StandardError.new("something went wrong")
        @timestamp = Time.now
      end

      should "return a hash with exception specific data including context hash" do
        exception_context = {
          "rack.session" => {
            user_id: 23,
            user_name: "John"
          }
        }

        exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "user_id" => 23, "user_name" => "John" },
          "environment" => {
            "rack.session" => { "user_id" => 23, "user_name" => "John" }
          }
        }

        assert_equal_with_diff expected_data, exception_info.data
      end

      should "generate exception data appropriately if exception message is nil" do
        exception_info = ExceptionInfo.new(exception_with_nil_message, "custom context data", @timestamp)
        exception_data = exception_info.data
        assert_equal "RuntimeError: ", exception_data["error_string"]
        assert_equal "RuntimeError: : custom context data", exception_data["error"]
      end

      should "return a hash with exception specific data including context string" do
        exception_context = "custom context data"
        exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong: custom context data",
          "environment" => {
            "message" => "custom context data"
          }
        }

        assert_equal_with_diff expected_data, exception_info.data
      end

      should "not include enhanced data from controller or custom data callback" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435 }
        session = { username: "jsmith" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        data_callback = ->(data) { data[:custom_section] = "value" }
        exception_info = ExceptionInfo.new(@exception, "custom context data", @timestamp, controller: controller, data_callback: data_callback)

        dont_allow(exception_info).extract_and_merge_controller_data
        dont_allow(exception_info).customize_from_data_callback
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong: custom context data",
          "environment" => {
            "message" => "custom context data"
          }
        }

        assert_equal_with_diff expected_data, exception_info.data
      end
    end

    context "enhanced_data" do
      setup do
        @exception = StandardError.new("something went wrong")
        @timestamp = Time.now
        @exception_context = {
          "rack.session" => {
            user_id: 23,
            user_name: "John"
          },
          "SERVER_NAME" => "exceptional.com"
        }
        env = { server: "fe98" }
        parameters = { advertiser_id: 435, controller: "dummy", action: "fail" }
        session = { username: "jsmith", id: "session_key" }
        request_uri = "host/path"
        @controller = create_dummy_controller(env, parameters, session, request_uri)
        @data_callback = ->(data) { data[:custom_section] = "check this out" }
      end

      should "not return a mutable object for the session" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        exception_info.enhanced_data["session"]["hello"] = "world"
        assert_nil @controller.session["hello"]
      end

      should "return a hash with generic exception attributes as well as context data" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "user_id" => 23, "user_name" => "John" },
          "environment" => { "SERVER_NAME" => "exceptional.com" },
          "location" => { "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, prepare_data(exception_info.enhanced_data)
      end

      should "generate exception data appropriately if exception message is nil" do
        exception_with_nil_message = RuntimeError.new(nil)
        stub(exception_with_nil_message).message { nil }
        exception_info = ExceptionInfo.new(exception_with_nil_message, @exception_context, @timestamp)
        exception_data = exception_info.enhanced_data
        assert_equal "RuntimeError: ", exception_data["error_string"]
        assert_equal "RuntimeError: ", exception_data["error"]
      end

      should "include controller data when available" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: @controller)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "key" => "session_key", "data" => { "username" => "jsmith", "id" => "session_key" } },
          "environment" => { "SERVER_NAME" => "exceptional.com" },
          "request" => {
            "params" => { "advertiser_id" => 435, "controller" => "dummy", "action" => "fail" },
            "rails_root" => "Rails.root not defined. Is this a test environment?",
            "url" => "host/path"
          },
          "location" => { "controller" => "dummy", "action" => "fail", "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, prepare_data(exception_info.enhanced_data)
      end

      should "extract controller from rack specific exception context when not provided explicitly" do
        @exception_context["action_controller.instance"] = @controller
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "key" => "session_key", "data" => { "username" => "jsmith", "id" => "session_key" } },
          "environment" => { "SERVER_NAME" => "exceptional.com" },
          "request" => {
            "params" => { "advertiser_id" => 435, "controller" => "dummy", "action" => "fail" },
            "rails_root" => "Rails.root not defined. Is this a test environment?",
            "url" => "host/path"
          },
          "location" => { "controller" => "dummy", "action" => "fail", "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, prepare_data(exception_info.enhanced_data)
      end

      should "add to_s attribute to specific sections that have their content in hash format" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: @controller)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => {
            "key" => "session_key",
            "data" => { "username" => "jsmith", "id" => "session_key" },
            "to_s" => "data:\n  id: session_key\n  username: jsmith\nkey: session_key\n"
          },
          "environment" => {
            "SERVER_NAME" => "exceptional.com",
            "to_s" => "SERVER_NAME: exceptional.com\n"
          },
          "request" => {
            "params" => { "advertiser_id" => 435, "controller" => "dummy", "action" => "fail" },
            "rails_root" => "Rails.root not defined. Is this a test environment?",
            "url" => "host/path",
            "to_s" => "params:\n  action: fail\n  advertiser_id: 435\n  controller: dummy\nrails_root: Rails.root not defined. Is this a test environment?\nurl: host/path\n"
          },
          "location" => { "controller" => "dummy", "action" => "fail", "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, exception_info.enhanced_data
      end

      should "filter out sensitive parameters like passwords" do
        @controller.request.parameters[:password] = "super_secret"
        @controller.request.parameters[:user] = { "password" => "also super secret", "password_confirmation" => "also super secret" }
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: @controller)
        expected_params = {
          "password" => "[FILTERED]",
          "advertiser_id" => 435, "controller" => "dummy",
          "action" => "fail",
          "user" => {
            "password" => "[FILTERED]",
            "password_confirmation" => "[FILTERED]"
          }
        }
        assert_equal_with_diff expected_params, exception_info.enhanced_data["request"]["params"]
      end

      should "include the changes from the custom data callback" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: nil, data_callback: @data_callback)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "user_id" => 23, "user_name" => "John" },
          "environment" => { "SERVER_NAME" => "exceptional.com" },
          "custom_section" => "check this out",
          "location" => { "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, prepare_data(exception_info.enhanced_data)
      end

      should "apply the custom_data_hook results" do
        stub(ExceptionHandling).custom_data_hook { ->(data) { data[:custom_hook] = "changes from custom hook" } }
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        expected_data = {
          "error_class" => "StandardError",
          "error_string" => "StandardError: something went wrong",
          "timestamp" => @timestamp,
          "backtrace" => ["<no backtrace>"],
          "error" => "StandardError: something went wrong",
          "session" => { "user_id" => 23, "user_name" => "John" },
          "environment" => { "SERVER_NAME" => "exceptional.com" },
          "custom_hook" => "changes from custom hook",
          "location" => { "file" => "<no backtrace>", "line" => nil }
        }

        assert_equal_with_diff expected_data, prepare_data(exception_info.enhanced_data)
      end

      should "log info if the custom data hook results in a nil message exception" do
        ExceptionHandling.custom_data_hook = ->(_data) do
          raise_exception_with_nil_message
        end
        log_info_messages = []
        stub(ExceptionHandling.logger).info.with_any_args do |message, _|
          log_info_messages << message
        end

        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        exception_info.enhanced_data
        assert log_info_messages.find { |message| message =~ /Unable to execute custom custom_data_hook callback/ }
        ExceptionHandling.custom_data_hook = nil
      end
    end

    context "exception_description" do
      should "return the exception description from the global exception filter list" do
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        description = exception_info.exception_description
        assert_not_nil description
        assert_equal :NoRoute, description.filter_name
      end

      should "find the description when filter criteria includes section in hash format" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435, controller: "sessions", action: "fail" }
        session = { username: "jsmith", id: "session_key" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        exception = StandardError.new("Request to click domain rejected")
        exception_info = ExceptionInfo.new(exception, nil, Time.now, controller: controller)
        assert_equal true, exception_info.enhanced_data[:request].is_a?(Hash)
        description = exception_info.exception_description
        assert_not_nil description
        assert_equal :"Click Request Rejected", description.filter_name
      end

      should "return same description object for related errors (avoid reloading exception catalog from disk)" do
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        description = exception_info.exception_description

        repeat_ex = StandardError.new("No route matches 2")
        repeat_ex_info = ExceptionInfo.new(repeat_ex, nil, Time.now)
        assert_equal description.object_id, repeat_ex_info.exception_description.object_id
      end
    end

    context "controller_name" do
      setup do
        @exception = StandardError.new('something went wrong')
        @timestamp = Time.now
        @exception_context = {
          'rack.session' => {
            user_id: 23,
            user_name: 'John'
          },
          'SERVER_NAME' => 'exceptional.com'
        }
      end

      should "return controller_name when controller is present" do
        env         = { server:     'fe98' }
        parameters  = { controller: 'some_controller' }
        session     = { username:   'smith' }
        request_uri = "host/path"
        controller  = create_dummy_controller(env, parameters, session, request_uri)
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: controller)

        assert_equal 'some_controller', exception_info.controller_name
      end

      should "return an empty string when controller is not present" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)

        assert_equal '', exception_info.controller_name
      end
    end

    context "send_to_honeybadger?" do
      should "be enabled when Honeybadger is defined and exception is not in the filter list" do
        stub(ExceptionHandling).honeybadger_defined? { true }
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        assert_nil exception_info.exception_description
        assert_equal true, exception_info.send_to_honeybadger?
      end

      should "be enabled when Honeybadger is defined and exception is on the filter list with the flag turned on" do
        stub(ExceptionHandling).honeybadger_defined? { true }
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        assert_not_nil exception_info.exception_description
        assert_equal true, exception_info.exception_description.send_to_honeybadger
        assert_equal true, exception_info.send_to_honeybadger?
      end

      should "be disabled when Honeybadger is defined and exception is on the filter list with the flag turned off" do
        stub(ExceptionHandling).honeybadger_defined? { true }
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        assert_not_nil exception_info.exception_description
        stub(exception_info.exception_description).send_to_honeybadger { false }
        assert_equal false, exception_info.send_to_honeybadger?
      end

      should "be disabled when Honeybadger is not defined" do
        stub(ExceptionHandling).honeybadger_defined? { false }
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        assert_nil exception_info.exception_description
        assert_equal false, exception_info.send_to_honeybadger?
      end
    end

    context "honeybadger_context_data" do
      should "return the error details and relevant context data to be used as honeybadger notification context while filtering sensitive data" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435 }
        session = { username: "jsmith" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        stub(ExceptionHandling).server_name { "invoca_fe98" }

        exception = StandardError.new("Some Exception")
        exception.set_backtrace([
                                  "test/unit/exception_handling_test.rb:847:in `exception_1'",
                                  "test/unit/exception_handling_test.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"
                                ])
        exception_context = { "SERVER_NAME" => "exceptional.com" }
        data_callback = ->(data) do
          data[:scm_revision] = "5b24eac37aaa91f5784901e9aabcead36fd9df82"
          data[:user_details] = { username: "jsmith" }
          data[:event_response] = "Event successfully received"
          data[:other_section] = "This should not be included in the response"
        end
        timestamp = Time.now
        exception_info = ExceptionInfo.new(exception, exception_context, timestamp, controller: controller, data_callback: data_callback)

        expected_data = {
          timestamp: timestamp,
          error_class: "StandardError",
          exception_context: { "SERVER_NAME" => "exceptional.com" },
          server: "invoca_fe98",
          scm_revision: "5b24eac37aaa91f5784901e9aabcead36fd9df82",
          notes: "this is used by a test",
          user_details: { "username" => "jsmith" },
          request: {
            "params" => { "advertiser_id" => 435 },
            "rails_root" => "Rails.root not defined. Is this a test environment?",
            "url" => "host/path"
          },
          session: {
            "key" => nil,
            "data" => { "username" => "jsmith" }
          },
          environment: {
            "SERVER_NAME" => "exceptional.com"
          },
          backtrace: [
            "test/unit/exception_handling_test.rb:847:in `exception_1'",
            "test/unit/exception_handling_test.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"
          ],
          event_response: "Event successfully received"
        }
        assert_equal_with_diff expected_data, exception_info.honeybadger_context_data
      end

      [['Hash',   { 'cookie' => 'cookie_context' }],
       ['String', 'Entering Error State'],
       ['Array',  ['Error1', 'Error2']]].each do |klass, value|
        should "extract context from exception_context when it is a #{klass}" do
          exception = StandardError.new("Exception")
          exception_context = value
          exception_info = ExceptionInfo.new(exception, exception_context, Time.now)

          assert_equal klass, value.class.name
          assert_equal value, exception_info.honeybadger_context_data[:exception_context]
        end
      end

      should "filter out sensitive data from exception context such as [password, password_confirmation, oauth_token]" do
        sensitive_data = {
          "password" => "super_secret",
          "password_confirmation" => "super_secret_confirmation",
          "oauth_token" => "super_secret_oauth_token"
        }

        exception         = StandardError.new("boom")
        exception_context = {
          "SERVER_NAME" => "exceptional.com",
          "one_layer" => sensitive_data,
          "two_layers" => {
            "sensitive_data" => sensitive_data
          },
          "rack.request.form_vars" => "username=investor%40invoca.com&password=my_special_password&commit=Log+In",
          "example_without_password" => {
            "rack.request.form_vars" => "username=investor%40invoca.com"
          }
        }.merge(sensitive_data)

        exception_info = ExceptionInfo.new(exception, exception_context, Time.now)

        expected_sensitive_data = ["password", "password_confirmation", "oauth_token"].build_hash { |key| [key, "[FILTERED]"] }
        expected_exception_context = {
          "SERVER_NAME" => "exceptional.com",
          "one_layer" => expected_sensitive_data,
          "two_layers" => {
            "sensitive_data" => expected_sensitive_data
          },
          "rack.request.form_vars" => "username=investor%40invoca.com&password=[FILTERED]&commit=Log+In",
          "example_without_password" => {
            "rack.request.form_vars" => "username=investor%40invoca.com"
          }
        }.merge(expected_sensitive_data)

        assert_equal_with_diff expected_exception_context, exception_info.honeybadger_context_data[:exception_context]
      end

      should "omit context if exception_context is empty" do
        exception = StandardError.new("Exception")
        exception_context = ""
        exception_info = ExceptionInfo.new(exception, exception_context, Time.now)

        assert_nil exception_info.honeybadger_context_data[:exception_context]
      end
    end

    def prepare_data(data)
      data.each do |_key, section|
        if section.is_a?(Hash)
          section.delete(:to_s)
        end
      end
    end
  end
end
