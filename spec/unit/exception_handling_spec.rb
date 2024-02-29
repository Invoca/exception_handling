# frozen_string_literal: true

require File.expand_path('../spec_helper',  __dir__)
require_test_helper 'controller_helpers'
require_test_helper 'exception_helpers'

describe ExceptionHandling do
  include ControllerHelpers
  include ExceptionHelpers

  before do
    @fail_count = 0
  end

  def dont_stub_log_error
    true
  end

  def append_organization_info_config(data)
    data[:user_details]                = {}
    data[:user_details][:username]     = "CaryP"
    data[:user_details][:organization] = "Invoca Engineering Dept."
  rescue StandardError
    # don't let these out!
  end

  def custom_data_callback_returns_nil_message_exception(_data)
    raise_exception_with_nil_message
  end

  def log_error_callback(_data, _ex, _treat_like_warning, _honeybadger_status)
    @fail_count += 1
  end

  def log_error_callback_config(data, _ex, treat_like_warning, honeybadger_status)
    @callback_data = data
    @treat_like_warning = treat_like_warning
    @fail_count += 1
    @honeybadger_status = honeybadger_status
  end

  def log_error_callback_with_failure(_data, _ex)
    raise "this should be rescued"
  end

  def log_error_callback_returns_nil_message_exception(_data, _ex)
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

      def resolve(_hostname)
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

  before(:each) do
    # Reset this for every test since they are applied to the class
    ExceptionHandling.honeybadger_auto_tagger = nil
  end

  context "with warn and honeybadger notify stubbed" do
    before do
      allow(ExceptionHandling).to receive(:warn).with(any_args)
      allow(Honeybadger).to receive(:notify).with(any_args)
    end

    context "with logger stashed" do
      before { @original_logger = ExceptionHandling.logger }
      after { ExceptionHandling.logger = @original_logger }

      it "stores logger as-is if it has ContextualLogger::Mixin" do
        logger = Logger.new('/dev/null')
        logger.extend(ContextualLogger::LoggerMixin)
        ancestors = logger.singleton_class.ancestors.*.name

        ExceptionHandling.logger = logger
        expect(ExceptionHandling.logger.singleton_class.ancestors.*.name).to eq(ancestors)
      end

      it "allows logger = nil (no deprecation warning)" do
        expect(STDERR).to receive(:puts).with(/DEPRECATION WARNING/).never
        ExceptionHandling.logger = nil
      end

      context "#log_error" do
        it "takes in additional logging context hash and pass it to the logger" do
          ExceptionHandling.log_error('This is an Error', 'This is the prefix context', service_name: 'exception_handling')
          expect(logged_excluding_reload_filter.last[:message]).to match(/This is an Error/)
          expect(logged_excluding_reload_filter.last[:context]).to_not be_empty
          expect(service_name: 'exception_handling').to eq(logged_excluding_reload_filter.last[:context])
        end

        it "passes :honeybadger_tags in log context to honeybadger" do
          expect(Honeybadger).to receive(:notify).with(hash_including({ tags: "  , awesome  ,  totallytubular,  " }))
          ExceptionHandling.log_error('This is an Error', 'This is the prefix context', honeybadger_tags: '  , awesome  ,  totallytubular,  ')

          expect(Honeybadger).to receive(:notify).with(hash_including({ tags: "    cool  neat" }))
          ExceptionHandling.log_error('This is an Error', 'This is the prefix context', honeybadger_tags: ["  ", " cool ", "neat"])
        end

        it "logs with Severity::FATAL" do
          ExceptionHandling.log_error('This is a Warning', service_name: 'exception_handling')
          expect('FATAL').to eq(logged_excluding_reload_filter.last[:severity])
        end
      end
    end

    context "#log_warning" do
      it "have empty array as a backtrace" do
        expect(ExceptionHandling).to receive(:log_error) do |error|
          expect(error.class).to eq(ExceptionHandling::Warning)
          expect(error.backtrace).to eq([])
        end
        ExceptionHandling.log_warning('Now with empty array as a backtrace!')
      end

      it "take in additional key word args as logging context and pass them to the logger" do
        ExceptionHandling.log_warning('This is a Warning', service_name: 'exception_handling')
        expect(logged_excluding_reload_filter.last[:message]).to match(/This is a Warning/)
        expect(logged_excluding_reload_filter.last[:context]).to_not be_empty
        expect(service_name: 'exception_handling').to eq(logged_excluding_reload_filter.last[:context])
      end

      it "log with Severity::WARN" do
        ExceptionHandling.log_warning('This is a Warning', service_name: 'exception_handling')
        expect('WARN').to eq(logged_excluding_reload_filter.last[:severity])
      end
    end

    context "#log_info" do
      it "take in additional key word args as logging context and pass them to the logger" do
        ExceptionHandling.log_info('This is an Info', service_name: 'exception_handling')
        expect(logged_excluding_reload_filter.last[:message]).to match(/This is an Info/)
        expect(logged_excluding_reload_filter.last[:context]).to_not be_empty
        expect(service_name: 'exception_handling').to eq(logged_excluding_reload_filter.last[:context])
      end

      it "log with Severity::INFO" do
        ExceptionHandling.log_info('This is a Warning', service_name: 'exception_handling')
        expect('INFO').to eq(logged_excluding_reload_filter.last[:severity])
      end
    end

    context "#log_debug" do
      it "take in additional key word args as logging context and pass them to the logger" do
        ExceptionHandling.log_debug('This is a Debug', service_name: 'exception_handling')
        expect(logged_excluding_reload_filter.last[:message]).to match(/This is a Debug/)
        expect(logged_excluding_reload_filter.last[:context]).to_not be_empty
        expect(service_name: 'exception_handling').to eq(logged_excluding_reload_filter.last[:context])
      end

      it "log with Severity::DEBUG" do
        ExceptionHandling.log_debug('This is a Warning', service_name: 'exception_handling')
        expect('DEBUG').to eq(logged_excluding_reload_filter.last[:severity])
      end
    end

    context "#write_exception_to_log" do
      it "log warnings with Severity::WARN" do
        warning = ExceptionHandling::Warning.new('This is a Warning')
        ExceptionHandling.write_exception_to_log(warning, '', Time.now.to_i, service_name: 'exception_handling')
        expect('WARN').to eq(logged_excluding_reload_filter.last[:severity])
      end

      it "log everything else with Severity::FATAL" do
        error = RuntimeError.new('This is a runtime error')
        ExceptionHandling.write_exception_to_log(error, '', Time.now.to_i, service_name: 'exception_handling')
        expect('FATAL').to eq(logged_excluding_reload_filter.last[:severity])
      end
    end

    context "configuration with custom_data_hook or post_log_error_hook" do
      after do
        ExceptionHandling.custom_data_hook = nil
        ExceptionHandling.post_log_error_hook = nil
      end

      it "support a custom_data_hook" do
        capture_notifications

        ExceptionHandling.custom_data_hook = method(:append_organization_info_config)
        ExceptionHandling.ensure_safe("context") { raise "Some Exception" }

        expect(sent_notifications.last.enhanced_data['user_details'].to_s).to match(/Invoca Engineering Dept./)
      end

      it "support a log_error hook, and pass exception_data, treat_like_warning, and logged_to_honeybadger to it" do
        @honeybadger_status = nil
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)

        notify_args = []
        expect(Honeybadger).to receive(:notify).with(any_args) { |info| notify_args << info; '06220c5a-b471-41e5-baeb-de247da45a56' }
        ExceptionHandling.ensure_safe("context") { raise "Some Exception" }
        expect(@fail_count).to eq(1)
        expect(@treat_like_warning).to eq(false)
        expect(@honeybadger_status).to eq(:success)

        expect(@callback_data["notes"]).to eq("this is used by a test")
        expect(notify_args.size).to eq(1), notify_args.inspect
        expect(notify_args.last[:context].to_s).to match(/this is used by a test/)
      end

      it "plumb treat_like_warning and logged_to_honeybadger to log error hook" do
        @honeybadger_status = nil
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
        ExceptionHandling.log_error(StandardError.new("Some Exception"), "mooo", treat_like_warning: true)
        expect(@fail_count).to eq(1)
        expect(@treat_like_warning).to eq(true)
        expect(@honeybadger_status).to eq(:skipped)
      end

      it "include logging context in the exception data" do
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
        ExceptionHandling.log_error(StandardError.new("Some Exception"), "mooo", treat_like_warning: true, log_context_test: "contextual_logging")

        expected_log_context = {
          "log_context_test" => "contextual_logging"
        }
        expect(@callback_data[:log_context]).to eq(expected_log_context)
      end

      it "support rescue exceptions from a log_error hook" do
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_with_failure)
        log_info_messages = []
        allow(ExceptionHandling.logger).to receive(:info).with(any_args) do |message, _|
          log_info_messages << message
        end
        expect { ExceptionHandling.ensure_safe("mooo") { raise "Some Exception" } }.to_not raise_error
        expect(log_info_messages.find { |message| message =~ /Unable to execute custom log_error callback/ }).to be_truthy
      end

      it "handle nil message exceptions resulting from the log_error hook" do
        ExceptionHandling.post_log_error_hook = method(:log_error_callback_returns_nil_message_exception)
        log_info_messages = []
        allow(ExceptionHandling.logger).to receive(:info).with(any_args) do |message, _|
          log_info_messages << message
        end
        expect { ExceptionHandling.ensure_safe("mooo") { raise "Some Exception" } }.to_not raise_error
        expect(log_info_messages.find { |message| message =~ /Unable to execute custom log_error callback/ }).to be_truthy
      end

      it "handle nil message exceptions resulting from the custom data hook" do
        ExceptionHandling.custom_data_hook = method(:custom_data_callback_returns_nil_message_exception)
        log_info_messages = []
        allow(ExceptionHandling.logger).to receive(:info).with(any_args) do |message, _|
          log_info_messages << message
        end
        expect { ExceptionHandling.ensure_safe("mooo") { raise "Some Exception" } }.not_to raise_error
        expect(log_info_messages.find { |message| message =~ /Unable to execute custom custom_data_hook callback/ }).to be_truthy
      end
    end

    context "Exception Handling" do
      context "default_metric_name" do
        context "with include_prefix true" do
          it "logs a deprecation warning" do
            expect { ExceptionHandling.default_metric_name({}, StandardError.new('this is an exception'), false) }
              .to output(/DEPRECATION WARNING: the 'expection_handling\.' prefix in ExceptionHandling::default_metric_name is deprecated/).to_stderr
          end

          context "when metric_name is present in exception_data" do
            it "include metric_name in resulting metric name" do
              exception = StandardError.new('this is an exception')
              metric    = ExceptionHandling.default_metric_name({ 'metric_name' => 'special_metric' }, exception, true, include_prefix: true)
              expect(metric).to eq('exception_handling.special_metric')
            end
          end

          context "when metric_name is not present in exception_data" do
            it "return exception_handling.warning when using log warning" do
              warning = ExceptionHandling::Warning.new('this is a warning')
              metric  = ExceptionHandling.default_metric_name({}, warning, false, include_prefix: true)
              expect(metric).to eq('exception_handling.warning')
            end

            it "return exception_handling.exception when using log error" do
              exception = StandardError.new('this is an exception')
              metric    = ExceptionHandling.default_metric_name({}, exception, false, include_prefix: true)
              expect(metric).to eq('exception_handling.exception')
            end

            context "when using log error with treat_like_warning" do
              it "return exception_handling.unforwarded_exception when exception not present" do
                metric = ExceptionHandling.default_metric_name({}, nil, true, include_prefix: true)
                expect(metric).to eq('exception_handling.unforwarded_exception')
              end

              it "return exception_handling.unforwarded_exception with exception classname when exception is present" do
                module SomeModule
                  class SomeException < StandardError
                  end
                end

                exception = SomeModule::SomeException.new('this is an exception')
                metric    = ExceptionHandling.default_metric_name({}, exception, true, include_prefix: true)
                expect(metric).to eq('exception_handling.unforwarded_exception_SomeException')
              end
            end
          end
        end

        context "with include_prefix false" do
          context "when metric_name is present in exception_data" do
            it "include metric_name in resulting metric name" do
              exception = StandardError.new('this is an exception')
              metric    = ExceptionHandling.default_metric_name({ 'metric_name' => 'special_metric' }, exception, true, include_prefix: false)
              expect(metric).to eq('special_metric')
            end
          end

          context "when metric_name is not present in exception_data" do
            it "return exception_handling.warning when using log warning" do
              warning = ExceptionHandling::Warning.new('this is a warning')
              metric  = ExceptionHandling.default_metric_name({}, warning, false, include_prefix: false)
              expect(metric).to eq('warning')
            end

            it "return exception_handling.exception when using log error" do
              exception = StandardError.new('this is an exception')
              metric    = ExceptionHandling.default_metric_name({}, exception, false, include_prefix: false)
              expect(metric).to eq('exception')
            end

            context "when using log error with treat_like_warning" do
              it "return exception_handling.unforwarded_exception when exception not present" do
                metric = ExceptionHandling.default_metric_name({}, nil, true, include_prefix: false)
                expect(metric).to eq('unforwarded_exception')
              end

              it "return exception_handling.unforwarded_exception with exception classname when exception is present" do
                module SomeModule
                  class SomeException < StandardError
                  end
                end

                exception = SomeModule::SomeException.new('this is an exception')
                metric    = ExceptionHandling.default_metric_name({}, exception, true, include_prefix: false)
                expect(metric).to eq('unforwarded_exception_SomeException')
              end
            end
          end
        end
      end

      context "default_honeybadger_metric_name" do
        it "return exception_handling.honeybadger.success when status is :success" do
          metric = ExceptionHandling.default_honeybadger_metric_name(:success)
          expect(metric).to eq('exception_handling.honeybadger.success')
        end

        it "return exception_handling.honeybadger.failure when status is :failure" do
          metric = ExceptionHandling.default_honeybadger_metric_name(:failure)
          expect(metric).to eq('exception_handling.honeybadger.failure')
        end

        it "return exception_handling.honeybadger.skipped when status is :skipped" do
          metric = ExceptionHandling.default_honeybadger_metric_name(:skipped)
          expect(metric).to eq('exception_handling.honeybadger.skipped')
        end

        it "return exception_handling.honeybadger.unknown_status when status is not recognized" do
          metric = ExceptionHandling.default_honeybadger_metric_name(nil)
          expect(metric).to eq('exception_handling.honeybadger.unknown_status')
        end
      end

      context "ExceptionHandling.ensure_safe" do
        it "log an exception with call stack if an exception is raised." do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(blah\):\n.*exception_handling_spec\.rb/, any_args)
          ExceptionHandling.ensure_safe { raise ArgumentError, "blah" }
        end

        it "should not log an exception if an exception is not raised." do
          expect(ExceptionHandling.logger).to_not receive(:fatal)
          ExceptionHandling.ensure_safe { ; }
        end

        it "return its value if used during an assignment" do
          expect(ExceptionHandling.logger).to_not receive(:fatal)
          b = ExceptionHandling.ensure_safe { 5 }
          expect(b).to eq(5)
        end

        it "return nil if an exception is raised during an assignment" do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(blah\):\n.*exception_handling_spec\.rb/, any_args)
          b = ExceptionHandling.ensure_safe { raise ArgumentError, "blah" }
          expect(b).to be_nil
        end

        it "allow a message to be appended to the error when logged." do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/mooo\nArgumentError: \(blah\):\n.*exception_handling_spec\.rb/, any_args)
          b = ExceptionHandling.ensure_safe("mooo") { raise ArgumentError, "blah" }
          expect(b).to be_nil
        end

        it "only rescue StandardError and descendents" do
          expect { ExceptionHandling.ensure_safe("mooo") { raise Exception } }.to raise_exception(Exception)

          expect(ExceptionHandling.logger).to receive(:fatal).with(/mooo\nStandardError: \(blah\):\n.*exception_handling_spec\.rb/, any_args)

          b = ExceptionHandling.ensure_safe("mooo") { raise StandardError, "blah" }
          expect(b).to be_nil
        end
      end

      context "ExceptionHandling.ensure_completely_safe" do
        it "log an exception if an exception is raised." do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(blah\):\n.*exception_handling_spec\.rb/, any_args)
          ExceptionHandling.ensure_completely_safe { raise ArgumentError, "blah" }
        end

        it "should not log an exception if an exception is not raised." do
          expect(ExceptionHandling.logger).to receive(:fatal).exactly(0)
          ExceptionHandling.ensure_completely_safe { ; }
        end

        it "return its value if used during an assignment" do
          expect(ExceptionHandling.logger).to receive(:fatal).exactly(0)
          b = ExceptionHandling.ensure_completely_safe { 5 }
          expect(b).to eq(5)
        end

        it "return nil if an exception is raised during an assignment" do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(blah\):\n.*exception_handling_spec\.rb/, any_args) { nil }
          b = ExceptionHandling.ensure_completely_safe { raise ArgumentError, "blah" }
          expect(b).to be_nil
        end

        it "allow a message to be appended to the error when logged." do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/mooo\nArgumentError: \(blah\):\n.*exception_handling_spec\.rb/, any_args)
          b = ExceptionHandling.ensure_completely_safe("mooo") { raise ArgumentError, "blah" }
          expect(b).to be_nil
        end

        it "rescue any instance or child of Exception" do
          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(blah\):\n.*exception_handling_spec\.rb/, any_args)
          ExceptionHandling.ensure_completely_safe { raise Exception, "blah" }
        end

        it "not rescue the special exceptions that Ruby uses" do
          [SystemExit, SystemStackError, NoMemoryError, SecurityError].each do |exception|
            expect do
              ExceptionHandling.ensure_completely_safe do
                raise exception
              end
            end.to raise_exception(exception)
          end
        end
      end

      context "exception timestamp" do
        before do
          Time.now_override = Time.parse('1986-5-21 4:17 am UTC')
        end

        it "include the timestamp when the exception is logged" do
          capture_notifications

          expect(ExceptionHandling.logger).to receive(:fatal).with(/\(Error:517033020\) context\nArgumentError: \(blah\):\n.*exception_handling_spec\.rb/, any_args)
          b = ExceptionHandling.ensure_safe("context") { raise ArgumentError, "blah" }
          expect(b).to be_nil

          expect(ExceptionHandling.last_exception_timestamp).to eq(517_033_020)

          expect(sent_notifications.size).to eq(1), sent_notifications.inspect

          expect(sent_notifications.last.enhanced_data['timestamp']).to eq(517_033_020)
        end
      end

      it "log the error if the exception message is nil" do
        capture_notifications

        ExceptionHandling.log_error(exception_with_nil_message)

        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
        expect(sent_notifications.last.enhanced_data['error_string']).to eq('RuntimeError: ')
      end

      it "log the error if the exception message is nil and the exception context is a hash" do
        capture_notifications

        ExceptionHandling.log_error(exception_with_nil_message, "SERVER_NAME" => "exceptional.com")

        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
        expect(sent_notifications.last.enhanced_data['error_string']).to eq('RuntimeError: ')
      end

      context "Honeybadger integration" do
        context "with Honeybadger not defined" do
          before do
            allow(ExceptionHandling).to receive(:honeybadger_defined?) { false }
          end

          it "not invoke send_exception_to_honeybadger when log_error is executed" do
            expect(ExceptionHandling).to_not receive(:send_exception_to_honeybadger)
            ExceptionHandling.log_error(exception_1)
          end

          it "not invoke send_exception_to_honeybadger when ensure_safe is executed" do
            expect(ExceptionHandling).to_not receive(:send_exception_to_honeybadger)
            ExceptionHandling.ensure_safe { raise exception_1 }
          end
        end

        context "with Honeybadger defined" do
          it "not send_exception_to_honeybadger when log_warning is executed" do
            expect(ExceptionHandling).to_not receive(:send_exception_to_honeybadger)
            ExceptionHandling.log_warning("This should not go to honeybadger")
          end

          it "not send_exception_to_honeybadger when log_error is called with a Warning" do
            expect(ExceptionHandling).to_not receive(:send_exception_to_honeybadger)
            ExceptionHandling.log_error(ExceptionHandling::Warning.new("This should not go to honeybadger"))
          end

          it "invoke send_exception_to_honeybadger when log_error is executed" do
            expect(ExceptionHandling).to receive(:send_exception_to_honeybadger).with(any_args).and_call_original
            ExceptionHandling.log_error(exception_1)
          end

          it "invoke send_exception_to_honeybadger when log_error_rack is executed" do
            expect(ExceptionHandling).to receive(:send_exception_to_honeybadger).with(any_args).and_call_original
            ExceptionHandling.log_error_rack(exception_1, {}, nil)
          end

          it "invoke send_exception_to_honeybadger when ensure_safe is executed" do
            expect(ExceptionHandling).to receive(:send_exception_to_honeybadger).with(any_args).and_call_original
            ExceptionHandling.ensure_safe { raise exception_1 }
          end

          it "specify error message as an empty string when notifying honeybadger if exception message is nil" do
            expect(Honeybadger).to receive(:notify).with(any_args) do |args|
              expect(args[:error_message]).to eq("")
            end
            ExceptionHandling.log_error(exception_with_nil_message)
          end

          context "with stubbed values" do
            before do
              Time.now_override = Time.now
              @env = { server: "fe98" }
              @parameters = { advertiser_id: 435, controller: "some_controller" }
              @session = { username: "jsmith" }
              @request_uri = "host/path"
              @controller = create_dummy_controller(@env, @parameters, @session, @request_uri)
              allow(ExceptionHandling).to receive(:server_name) { "invoca_fe98" }

              @exception = StandardError.new("Some Exception")
              @exception.set_backtrace([
                                         "spec/unit/exception_handling_spec.rb:847:in `exception_1'",
                                         "spec/unit/exception_handling_spec.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"
                                       ])
              @exception_context = { "SERVER_NAME" => "exceptional.com" }
            end

            it "send error details and relevant context data to Honeybadger with log_context" do
              honeybadger_data = nil
              expect(Honeybadger).to receive(:notify).with(any_args) do |data|
                honeybadger_data = data
              end
              ExceptionHandling.logger.global_context = { service_name: "rails", region: "AWS-us-east-1", honeybadger_tags: ['Data-Services', 'web'] }
              log_context = { log_source: "gem/listen", service_name: "bin/console" }
              ExceptionHandling.log_error(@exception, @exception_context, @controller, **log_context) do |data|
                data[:scm_revision] = "5b24eac37aaa91f5784901e9aabcead36fd9df82"
                data[:user_details] = { username: "jsmith" }
                data[:event_response] = "Event successfully received"
                data[:other_section] = "This should not be included in the response"
              end

              expected_data = {
                error_class: :"Test Exception",
                error_message: "Some Exception",
                controller: "some_controller",
                exception: @exception,
                tags: "Data-Services web",
                context: {
                  timestamp: Time.now.to_i,
                  error_class: "StandardError",
                  server: "invoca_fe98",
                  exception_context: { "SERVER_NAME" => "exceptional.com" },
                  scm_revision: "5b24eac37aaa91f5784901e9aabcead36fd9df82",
                  notes: "this is used by a test",
                  user_details: { "username" => "jsmith" },
                  request: {
                    "params" => { "advertiser_id" => 435, "controller" => "some_controller" },
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
                    "spec/unit/exception_handling_spec.rb:847:in `exception_1'",
                    "spec/unit/exception_handling_spec.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"
                  ],
                  event_response: "Event successfully received",
                  log_context: { "service_name" => "bin/console", "region" => "AWS-us-east-1", "log_source" => "gem/listen", "honeybadger_tags" => ['Data-Services', 'web'] }
                }
              }
              expect(honeybadger_data).to eq(expected_data)
            end

            it "send error details and relevant context data to Honeybadger with empty log_context" do
              honeybadger_data = nil
              expect(Honeybadger).to receive(:notify).with(any_args) do |data|
                honeybadger_data = data
              end
              ExceptionHandling.logger.global_context = {}
              log_context = {}
              ExceptionHandling.log_error(@exception, @exception_context, @controller, **log_context) do |data|
                data[:scm_revision] = "5b24eac37aaa91f5784901e9aabcead36fd9df82"
                data[:user_details] = { username: "jsmith" }
                data[:event_response] = "Event successfully received"
                data[:other_section] = "This should not be included in the response"
              end

              expected_data = {
                error_class: :"Test Exception",
                error_message: "Some Exception",
                controller: "some_controller",
                exception: @exception,
                tags: "",
                context: {
                  timestamp: Time.now.to_i,
                  error_class: "StandardError",
                  server: "invoca_fe98",
                  exception_context: { "SERVER_NAME" => "exceptional.com" },
                  scm_revision: "5b24eac37aaa91f5784901e9aabcead36fd9df82",
                  notes: "this is used by a test",
                  user_details: { "username" => "jsmith" },
                  request: {
                    "params" => { "advertiser_id" => 435, "controller" => "some_controller" },
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
                               "spec/unit/exception_handling_spec.rb:847:in `exception_1'",
                               "spec/unit/exception_handling_spec.rb:455:in `block (4 levels) in <class:ExceptionHandlingTest>'"
                             ],
                  event_response: "Event successfully received"
                }
              }
              expect(honeybadger_data).to eq(expected_data)
            end
          end

          context "with post_log_error_hook set" do
            after do
              ExceptionHandling.post_log_error_hook = nil
            end

            it "not send notification to honeybadger when exception description has the flag turned off and call log error callback with logged_to_honeybadger set to nil" do
              @honeybadger_status = nil
              ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
              filter_list = {
                NoHoneybadger: {
                  error: "suppress Honeybadger notification",
                  send_to_honeybadger: false
                }
              }
              allow(File).to receive(:mtime) { incrementing_mtime }
              expect(YAML).to receive(:load_file).with(any_args) { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }.at_least(1)

              expect(ExceptionHandling).to receive(:send_exception_to_honeybadger_unless_filtered).with(any_args).exactly(1).and_call_original
              expect(Honeybadger).to_not receive(:notify)
              ExceptionHandling.log_error(StandardError.new("suppress Honeybadger notification"))
              expect(@honeybadger_status).to eq(:skipped)
            end

            it "call log error callback with logged_to_honeybadger set to false if an error occurs while attempting to notify honeybadger" do
              @honeybadger_status = nil
              ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
              expect(Honeybadger).to receive(:notify).with(any_args) { raise "Honeybadger Notification Failure" }
              ExceptionHandling.log_error(exception_1)
              expect(@honeybadger_status).to eq(:failure)
            end

            it "call log error callback with logged_to_honeybadger set to false on unsuccessful honeybadger notification" do
              @honeybadger_status = nil
              ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
              expect(Honeybadger).to receive(:notify).with(any_args) { false }
              ExceptionHandling.log_error(exception_1)
              expect(@honeybadger_status).to eq(:failure)
            end

            it "call log error callback with logged_to_honeybadger set to true on successful honeybadger notification" do
              @honeybadger_status = nil
              ExceptionHandling.post_log_error_hook = method(:log_error_callback_config)
              expect(Honeybadger).to receive(:notify).with(any_args) { '06220c5a-b471-41e5-baeb-de247da45a56' }
              ExceptionHandling.log_error(exception_1)
              expect(@honeybadger_status).to eq(:success)
            end
          end
        end
      end

      class EventResponse
        def to_s
          "message from to_s!"
        end
      end

      it "allow sections to have data with just a to_s method" do
        capture_notifications

        ExceptionHandling.log_error("This is my RingSwitch example.") do |data|
          data.merge!(event_response: EventResponse.new)
        end

        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
        expect(sent_notifications.last.enhanced_data['event_response'].to_s).to match(/message from to_s!/)
      end
    end

    it "return the error ID (timestamp)" do
      result = ExceptionHandling.log_error(RuntimeError.new("A runtime error"), "Runtime message")
      expect(result).to eq(ExceptionHandling.last_exception_timestamp)
    end

    it "rescue exceptions that happen in log_error" do
      allow(ExceptionHandling).to receive(:make_exception) { raise ArgumentError, "Bad argument" }
      expect(ExceptionHandling).to receive(:write_exception_to_log).with(satisfy { |ex| ex.to_s['Bad argument'] },
                                                     satisfy { |context| context['ExceptionHandlingError: log_error rescued exception while logging Runtime message'] },
                                                     any_args)
      ExceptionHandling.log_error(RuntimeError.new("A runtime error"), "Runtime message")
    end

    it "rescue exceptions that happen when log_error yields" do
      expect(ExceptionHandling).to receive(:write_exception_to_log).with(satisfy { |ex| ex.to_s['Bad argument'] },
                                                     satisfy { |context| context['Context message'] },
                                                     anything,
                                                     any_args)
      ExceptionHandling.log_error(ArgumentError.new("Bad argument"), "Context message") { |_data| raise 'Error!!!' }
    end

    context "Exception Filtering" do
      before do
        filter_list = { exception1: { 'error' => "my error message" },
                        exception2: { 'error' => "some other message", :session => "misc data" } }
        allow(YAML).to receive(:load_file) { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }

        # bump modified time up to get the above filter loaded
        allow(File).to receive(:mtime) { incrementing_mtime }
      end

      it "handle case where filter list is not found" do
        allow(YAML).to receive(:load_file) { raise Errno::ENOENT, "File not found" }

        capture_notifications

        ExceptionHandling.log_error("My error message is in list")
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
      end

      it "log exception and suppress email when exception is on filter list" do
        capture_notifications

        ExceptionHandling.log_error("Error message is not in list")
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect

        sent_notifications.clear
        ExceptionHandling.log_error("My error message is in list")
        expect(sent_notifications.size).to eq(0), sent_notifications.inspect
      end

      it "allow filtering exception on any text in exception data" do
        filters = { exception1: { session: "data: my extra session data" } }
        allow(YAML).to receive(:load_file) { ActiveSupport::HashWithIndifferentAccess.new(filters) }

        capture_notifications

        ExceptionHandling.log_error("No match here") do |data|
          data[:session] = {
            key: "@session_id",
            data: "my extra session data"
          }
        end
        expect(sent_notifications.size).to eq(0), sent_notifications.inspect

        ExceptionHandling.log_error("No match here") do |data|
          data[:session] = {
            key: "@session_id",
            data: "my extra session <no match!> data"
          }
        end
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
      end

      it "reload filter list on the next exception if file was modified" do
        capture_notifications

        ExceptionHandling.log_error("Error message is not in list")
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect

        filter_list = { exception1: { 'error' => "Error message is not in list" } }
        allow(YAML).to receive(:load_file) { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }
        allow(File).to receive(:mtime) { incrementing_mtime }

        sent_notifications.clear
        ExceptionHandling.log_error("Error message is not in list")
        expect(sent_notifications.size).to eq(0), sent_notifications.inspect
      end

      it "not consider filter if both error message and body do not match" do
        capture_notifications

        # error message matches, but not full text
        ExceptionHandling.log_error("some other message")
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect

        # now both match
        sent_notifications.clear
        ExceptionHandling.log_error("some other message") do |data|
          data[:session] = { some_random_key: "misc data" }
        end
        expect(sent_notifications.size).to eq(0), sent_notifications.inspect
      end

      it "skip environment keys not on whitelist" do
        capture_notifications

        ExceptionHandling.log_error("some message") do |data|
          data[:environment] = { SERVER_PROTOCOL: "HTTP/1.0", RAILS_SECRETS_YML_CONTENTS: 'password: VERY_SECRET_PASSWORD' }
        end
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect

        mail = sent_notifications.last
        environment = mail.enhanced_data['environment']

        expect(environment["RAILS_SECRETS_YML_CONTENTS"]).to be_nil, environment.inspect # this is not on whitelist).to be_nil
        expect(environment["SERVER_PROTOCOL"]).to be_truthy, environment.inspect # this is
      end

      it "omit environment defaults" do
        capture_notifications

        allow(ExceptionHandling).to receive(:send_exception_to_honeybadger).with(any_args) { |exception_info| sent_notifications << exception_info }

        ExceptionHandling.log_error("some message") do |data|
          data[:environment] = { SERVER_PORT: '80', SERVER_PROTOCOL: "HTTP/1.0" }
        end
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
        mail = sent_notifications.last
        environment = mail.enhanced_data['environment']

        expect(environment["SERVER_PORT"]).to be_nil, environment.inspect # this was default).to be_nil
        expect(environment["SERVER_PROTOCOL"]).to be_truthy, environment.inspect # this was not
      end

      it "reject the filter file if any contain all empty regexes" do
        filter_list = { exception1: { 'error' => "", :session => "" },
                        exception2: { 'error' => "is not in list", :session => "" } }
        allow(YAML).to receive(:load_file) { ActiveSupport::HashWithIndifferentAccess.new(filter_list) }
        allow(File).to receive(:mtime) { incrementing_mtime }

        capture_notifications

        ExceptionHandling.log_error("Error message is not in list")
        expect(sent_notifications.size).to eq(1), sent_notifications.inspect
      end

      it "reload filter file if filename changes" do
        catalog = ExceptionHandling.exception_catalog
        ExceptionHandling.filter_list_filename = "./config/other_exception_filters.yml"
        expect(ExceptionHandling.exception_catalog).to_not eq(catalog)
      end
    end

    context "Exception mapping" do
      before do
        @data = {
          environment: {
            'HTTP_HOST' => "localhost",
            'HTTP_REFERER' => "http://localhost/action/controller/instance",
          },
          session: {
            data: {
              affiliate_id: defined?(Affiliate) ? Affiliate.first.id : '1',
              edit_mode: true,
              advertiser_id: defined?(Advertiser) ? Advertiser.first.id : '1',
              username_id: defined?(Username) ? Username.first.id : '1',
              user_id: defined?(User) ? User.first.id : '1',
              flash: {},
              impersonated_organization_pk: 'Advertiser_1'
            }
          },
          request: {},
          backtrace: ["[GEM_ROOT]/gems/actionpack-2.1.0/lib/action_controller/filters.rb:580:in `call_filters'", "[GEM_ROOT]/gems/actionpack-2.1.0/lib/action_controller/filters.rb:601:in `run_before_filters'"],
          api_key: "none",
          error_class: "StandardError",
          error: 'Some error message'
        }
      end

      it "clean backtraces" do
        begin
          raise "test exception"
        rescue => ex
          backtrace = ex.backtrace
        end
        result = ExceptionHandling.send(:clean_backtrace, ex).to_s
        expect(backtrace).to_not eq(result)
      end

      it "return entire backtrace if cleaned is emtpy" do
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

          rails = double(Rails)
          expect(rails).to receive(:backtrace_cleaner) { Rails::BacktraceCleaner.new }
          rails.backtrace_cleaner

          ex = Exception.new
          ex.set_backtrace(backtrace)
          result = ExceptionHandling.send(:clean_backtrace, ex)
          expect(result).to eq(backtrace)
        ensure
          Object.send(:remove_const, :Rails)
        end
      end
    end

    context "log_perodically" do
      before do
        Time.now_override = Time.now # Freeze time
        ExceptionHandling.logger.clear
      end

      after do
        Time.now_override = nil
      end

      it "take in additional logging context and pass them to the logger" do
        ExceptionHandling.log_periodically(:test_context_with_periodic, 30.minutes, "this will be written", service_name: 'exception_handling')
        expect(logged_excluding_reload_filter.last[:context]).to_not be_empty
        expect(logged_excluding_reload_filter.last[:context]).to eq({ service_name: 'exception_handling' })
      end

      it "log immediately when we are expected to log" do
        ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will be written")
        expect(logged_excluding_reload_filter.size).to eq(1)

        Time.now_override = Time.now + 5.minutes
        ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will not be written")
        expect(logged_excluding_reload_filter.size).to eq(1)

        ExceptionHandling.log_periodically(:test_another_periodic_exception, 30.minutes, "this will be written")
        expect(logged_excluding_reload_filter.size).to eq(2)

        Time.now_override = Time.now + 26.minutes

        ExceptionHandling.log_periodically(:test_periodic_exception, 30.minutes, "this will be written")
        expect(logged_excluding_reload_filter.size).to eq(3)
      end
    end

    context "#honeybadger_auto_tagger=" do
      context "with proc that runs successfully" do
        before do
          ExceptionHandling.honeybadger_auto_tagger =
            ->(exception) do
              if exception.message =~ /donuts/
                ['donut-error', 'high-urgency']
              else
                ['low-urgency']
              end
            end
        end

        context "without manually passed tags" do
          let(:exception) { StandardError.new("We are out of chocolate milk") }

          it "adds tags from autotagger" do
            expect(Honeybadger).to receive(:notify).with(hash_including({ tags: "low-urgency" }))
            ExceptionHandling.log_error(exception, nil)
          end
        end

        context "with manually passed tags" do
          let(:exception) { StandardError.new("The donuts are burning") }

          it "merges tags from autotagger with manually passed tags" do
            expect(Honeybadger).to receive(:notify).with(hash_including({ tags: "donut-error high-urgency upset-customers" }))
            ExceptionHandling.log_error(exception, nil, honeybadger_tags: ["upset-customers"])
          end
        end
      end
    end

    context "with proc that raises an exception" do
      let(:exception) { StandardError.new("Something else occurred") }

      before do
        ExceptionHandling.honeybadger_auto_tagger = ->(_exception) { raise StandardError, "boom" }
      end

      it "logs a message and returns [] for the tags" do
        expect(Honeybadger).to receive(:notify).with(hash_including({ tags: "some-other-tag" }))
        expect(ExceptionHandling).to receive(:log_info).with(/Unable to execute honeybadger_auto_tags callback. boom/)
        ExceptionHandling.log_error(exception, nil, honeybadger_tags: ["some-other-tag"])
      end
    end
  end


  private

  def logged_excluding_reload_filter
    ExceptionHandling.logger.logged.select { |l| l[:message] !~ /Reloading filter list/ }
  end

  def incrementing_mtime
    @mtime ||= Time.now
    @mtime += 1.day
  end

  def exception_1
    @exception_1 ||=
      begin
        raise StandardError, "Exception 1"
      rescue => ex
        ex
      end
  end

  def exception_2
    @exception_2 ||=
      begin
        raise StandardError, "Exception 2"
      rescue => ex
        ex
      end
  end
end
