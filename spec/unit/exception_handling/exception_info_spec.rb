# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)
require_test_helper 'controller_helpers'
require_test_helper 'exception_helpers'

module ExceptionHandling
  describe ExceptionInfo do
    include ControllerHelpers
    include ExceptionHelpers

    context "initialize" do
      before do
        @exception = StandardError.new("something went wrong")
        @timestamp = Time.now
        @controller = Object.new
      end

      context "controller_from_context" do
        it "extract controller from context when not specified explicitly" do
          exception_context = {
            "action_controller.instance" => @controller
          }
          exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp)
          expect(exception_info.controller).to eq(@controller)
        end

        it "prefer the explicit controller over the one from context" do
          exception_context = {
            "action_controller.instance" => Object.new
          }
          exception_info = ExceptionInfo.new(@exception, exception_context, @timestamp, controller: @controller)
          expect(exception_info.controller).to eq(@controller)
          expect(exception_info.controller).not_to eq(exception_context["action_controller.instance"])
        end

        it "leave controller unset when not included in the context hash" do
          exception_info = ExceptionInfo.new(@exception, {}, @timestamp)
          expect(exception_info.controller).to be_nil
        end

        it "leave controller unset when context is not in hash format" do
          exception_info = ExceptionInfo.new(@exception, "string context", @timestamp)
          expect(exception_info.controller).to be_nil
        end
      end
    end

    context "data" do
      before do
        @exception = StandardError.new("something went wrong")
        @timestamp = Time.now
      end

      it "return a hash with exception specific data including context hash" do
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

        expect(exception_info.data).to eq(expected_data)
      end

      it "generate exception data appropriately if exception message is nil" do
        exception_info = ExceptionInfo.new(exception_with_nil_message, "custom context data", @timestamp)
        exception_data = exception_info.data
        expect(exception_data["error_string"]).to eq("RuntimeError: ")
        expect(exception_data["error"]).to eq("RuntimeError: : custom context data")
      end

      it "return a hash with exception specific data including context string" do
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
        expect(exception_info.data).to eq(expected_data)
      end

      it "not include enhanced data from controller or custom data callback" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435 }
        session = { username: "jsmith" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        data_callback = ->(data) { data[:custom_section] = "value" }
        exception_info = ExceptionInfo.new(@exception, "custom context data", @timestamp, controller: controller, data_callback: data_callback)

        expect(exception_info).to_not receive(:extract_and_merge_controller_data)
        expect(exception_info).to_not receive(:customize_from_data_callback)
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

        expect(exception_info.data).to eq(expected_data)
      end
    end

    context "enhanced_data" do
      before do
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

      it "not return a mutable object for the session" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        exception_info.enhanced_data["session"]["hello"] = "world"
        expect(@controller.session["hello"]).to be_nil
      end

      it "return a hash with generic exception attributes as well as context data" do
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

        expect(prepare_data(exception_info.enhanced_data)).to eq(expected_data)
      end

      it "generate exception data appropriately if exception message is nil" do
        exception_with_nil_message = RuntimeError.new(nil)
        allow(exception_with_nil_message).to receive(:message).and_return(nil)
        exception_info = ExceptionInfo.new(exception_with_nil_message, @exception_context, @timestamp)
        exception_data = exception_info.enhanced_data
        expect(exception_data["error_string"]).to eq("RuntimeError: ")
        expect(exception_data["error"]).to eq("RuntimeError: ")
      end

      it "include controller data when available" do
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

        expect(prepare_data(exception_info.enhanced_data)).to eq(expected_data)
      end

      it "extract controller from rack specific exception context when not provided explicitly" do
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

        expect(prepare_data(exception_info.enhanced_data)).to eq(expected_data)
      end

      it "add to_s attribute to specific sections that have their content in hash format" do
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

        expect(exception_info.enhanced_data).to eq(expected_data)
      end

      it "filter out sensitive parameters like passwords" do
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
        expect(exception_info.enhanced_data["request"]["params"]).to eq(expected_params)
      end

      it "include the changes from the custom data callback" do
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

        expect(prepare_data(exception_info.enhanced_data)).to eq(expected_data)
      end

      it "apply the custom_data_hook results" do
        allow(ExceptionHandling).to receive(:custom_data_hook).and_return(->(data) { data[:custom_hook] = "changes from custom hook" })
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

        expect(prepare_data(exception_info.enhanced_data)).to eq(expected_data)
      end

      it "log info if the custom data hook results in a nil message exception" do
        ExceptionHandling.custom_data_hook = ->(_data) do
          raise_exception_with_nil_message
        end
        log_info_messages = []
        allow(ExceptionHandling.logger).to receive(:info).with(any_args) do |message, _|
          log_info_messages << message
        end

        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)
        exception_info.enhanced_data
        expect(log_info_messages.find { |message| message =~ /Unable to execute custom custom_data_hook callback/ }).to be_truthy
        ExceptionHandling.custom_data_hook = nil
      end
    end

    context "exception_description" do
      it "return the exception description from the global exception filter list" do
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, {}, Time.now)
        description = exception_info.exception_description
        expect(description).to_not be_nil
        expect(description.filter_name).to eq(:NoRoute)
      end

      it "find the description when filter criteria includes section in hash format" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435, controller: "sessions", action: "fail" }
        session = { username: "jsmith", id: "session_key" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        exception = StandardError.new("Request to click domain rejected")
        exception_info = ExceptionInfo.new(exception, nil, Time.now, controller: controller)
        expect(exception_info.enhanced_data[:request].is_a?(Hash)).to eq(true)
        description = exception_info.exception_description
        expect(description).to_not be_nil
        expect(description.filter_name).to eq(:"Click Request Rejected")
      end

      it "return same description object for related errors (avoid reloading exception catalog from disk)" do
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        description = exception_info.exception_description

        repeat_ex = StandardError.new("No route matches 2")
        repeat_ex_info = ExceptionInfo.new(repeat_ex, nil, Time.now)
        expect(repeat_ex_info.exception_description.object_id).to eq(description.object_id)
      end
    end

    context "controller_name" do
      before do
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

      it "return controller_name when controller is present" do
        env         = { server:     'fe98' }
        parameters  = { controller: 'some_controller' }
        session     = { username:   'smith' }
        request_uri = "host/path"
        controller  = create_dummy_controller(env, parameters, session, request_uri)
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp, controller: controller)

        expect(exception_info.controller_name).to eq('some_controller')
      end

      it "return an empty string when controller is not present" do
        exception_info = ExceptionInfo.new(@exception, @exception_context, @timestamp)

        expect(exception_info.controller_name).to eq('')
      end
    end

    context "send_to_honeybadger?" do
      it "be enabled when Honeybadger is defined and exception is not in the filter list" do
        allow(ExceptionHandling).to receive(:honeybadger_defined?).and_return(true)
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        expect(exception_info.exception_description).to be_nil
        expect(exception_info.send_to_honeybadger?).to eq(true)
      end

      it "be enabled when Honeybadger is defined and exception is on the filter list with the flag turned on" do
        allow(ExceptionHandling).to receive(:honeybadger_defined?).and_return(true)
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        expect(exception_info.exception_description).to_not be_nil
        expect(exception_info.exception_description.send_to_honeybadger).to eq(true)
        expect(exception_info.send_to_honeybadger?).to eq(true)
      end

      it "be disabled when Honeybadger is defined and exception is on the filter list with the flag turned off" do
        allow(ExceptionHandling).to receive(:honeybadger_defined?).and_return(true)
        exception = StandardError.new("No route matches")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        expect(exception_info.exception_description).to_not be_nil
        allow(exception_info.exception_description).to receive(:send_to_honeybadger).and_return(false)
        expect(exception_info.send_to_honeybadger?).to eq(false)
      end

      it "be disabled when Honeybadger is not defined" do
        allow(ExceptionHandling).to receive(:honeybadger_defined?).and_return(false)
        exception = StandardError.new("something went wrong")
        exception_info = ExceptionInfo.new(exception, nil, Time.now)
        expect(exception_info.exception_description).to be_nil
        expect(exception_info.send_to_honeybadger?).to eq(false)
      end
    end

    context "honeybadger_context_data" do
      before do
        allow(ExceptionHandling.logger).to receive(:current_context_for_thread).and_return({ cuid: 'ABCD' })
      end

      it "include thread_context when log_context: is nil" do
        exception_with_nil_message = RuntimeError.new(nil)
        allow(exception_with_nil_message).to receive(:message).and_return(nil)
        exception_info = ExceptionInfo.new(exception_with_nil_message, @exception_context, @timestamp)
        honeybadger_context_data = exception_info.honeybadger_context_data
        expect(honeybadger_context_data[:log_context]).to eq({ "cuid" => 'ABCD' })
      end

      it "include thread context merged with log_context:" do
        exception_with_nil_message = RuntimeError.new(nil)
        allow(exception_with_nil_message).to receive(:message).and_return(nil)
        exception_info = ExceptionInfo.new(exception_with_nil_message, @exception_context, @timestamp, log_context: { url: 'http://example.com' })
        honeybadger_context_data = exception_info.honeybadger_context_data
        expect(honeybadger_context_data[:log_context]).to eq({ "cuid" => 'ABCD', "url" => 'http://example.com' })
      end

      it "return the error details and relevant context data to be used as honeybadger notification context while filtering sensitive data" do
        env = { server: "fe98" }
        parameters = { advertiser_id: 435 }
        session = { username: "jsmith" }
        request_uri = "host/path"
        controller = create_dummy_controller(env, parameters, session, request_uri)
        allow(ExceptionHandling).to receive(:server_name).and_return("invoca_fe98")

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
          event_response: "Event successfully received",
          log_context: { "cuid" => "ABCD" },
          notes: "this is used by a test"
        }
        expect(exception_info.honeybadger_context_data).to eq(expected_data)
      end

      [['Hash',   { 'cookie' => 'cookie_context' }],
       ['String', 'Entering Error State'],
       ['Array',  ['Error1', 'Error2']]].each do |klass, value|
        it "extract context from exception_context when it is a #{klass}" do
          exception = StandardError.new("Exception")
          exception_context = value
          exception_info = ExceptionInfo.new(exception, exception_context, Time.now)

          expect(value.class.name).to eq(klass)
          expect(exception_info.honeybadger_context_data[:exception_context]).to eq(value)
        end
      end

      it "filter out sensitive data from exception context such as [password, password_confirmation, oauth_token]" do
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

        expect(exception_info.honeybadger_context_data[:exception_context]).to eq(expected_exception_context)
      end

      it "omit context if exception_context is empty" do
        exception = StandardError.new("Exception")
        exception_context = ""
        exception_info = ExceptionInfo.new(exception, exception_context, Time.now)
        expect(exception_info.honeybadger_context_data[:exception_context]).to be_nil
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
