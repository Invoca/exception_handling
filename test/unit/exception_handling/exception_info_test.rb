require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class ExceptionInfoTest < ActiveSupport::TestCase

    DummyController = Struct.new(:complete_request_uri, :request, :session)

    DummyRequest = Struct.new(:env, :parameters, :session_options)

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
        exception_info = ExceptionInfo.new(@exception, "custom context data", @timestamp, controller, data_callback)

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

        assert_equal_with_diff expected_data, exception_info.enhanced_data
      end

      should "include controller data when available" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, @controller)
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

        assert_equal_with_diff expected_data, exception_info.enhanced_data
      end

      should "include the changes from the custom data callback" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, nil, @data_callback)
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

        assert_equal_with_diff expected_data, exception_info.enhanced_data
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

        assert_equal_with_diff expected_data, exception_info.enhanced_data
      end
    end

    should "return the exception description from the global exception filter list" do
      exception = StandardError.new("No route matches")
      exception_info = ExceptionInfo.new(exception, {}, Time.now)
      description = exception_info.exception_description
      assert_not_nil description
      assert_equal :NoRoute, description.filter_name
    end

    context "send_to_honeybadger?" do
      should "be enabled when Honeybadger is defined and exception is not in the filter list" do
        stub(ExceptionHandling).honeybadger? { true }
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        assert_nil exception_info.exception_description
        assert_equal true, exception_info.send_to_honeybadger?
      end

      should "be enabled when Honeybadger is defined and exception is on the filter list with the flag turned on" do
        stub(ExceptionHandling).honeybadger? { true }
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        assert_not_nil exception_info.exception_description
        assert_equal true, exception_info.exception_description.send_to_honeybadger
        assert_equal true, exception_info.send_to_honeybadger?
      end

      should "be disabled when Honeybadger is defined and exception is on the filter list with the flag turned off" do
        stub(ExceptionHandling).honeybadger? { true }
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        assert_not_nil exception_info.exception_description
        stub(exception_info.exception_description).send_to_honeybadger { false }
        assert_equal false, exception_info.send_to_honeybadger?
      end

      should "be disabled when Honeybadger is not defined" do
        stub(ExceptionHandling).honeybadger? { false }
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        assert_nil exception_info.exception_description
        assert_equal false, exception_info.send_to_honeybadger?
      end
    end

    def create_dummy_controller(env, parameters, session, request_uri)
      request = DummyRequest.new(env, parameters, session)
      DummyController.new(request_uri, request, session)
    end
  end
end
