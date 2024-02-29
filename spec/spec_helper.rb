# frozen_string_literal: true

require 'rspec'
require 'rspec/mocks'
require 'rspec_junit_formatter'

require 'pry'
require 'honeybadger'
require 'contextual_logger'

require 'exception_handling'
require 'exception_handling/testing'

class LoggerStub
  include ContextualLogger::LoggerMixin
  attr_accessor :logged, :level

  def initialize
    @level = Logger::Severity::DEBUG
    @progname = nil
    @logdev = nil
    clear
  end

  def debug(message, log_context = {})
    logged << { message: message, context: log_context, severity: 'DEBUG' }
  end

  def info(message, log_context = {})
    logged << { message: message, context: log_context, severity: 'INFO' }
  end

  def warn(message, log_context = {})
    logged << { message: message, context: log_context, severity: 'WARN' }
  end

  def fatal(message, log_context = {})
    logged << { message: message, context: log_context, severity: 'FATAL' }
  end

  def clear
    @logged = []
  end
end

class SocketStub
  attr_accessor :sent, :connected

  def initialize
    @connected = true
    clear
  end

  def send(message, _flags)
    sent << message
  end

  def close
    @connected = false
  end

  def clear
    @sent = []
  end

  def closed?
    !@connected
  end
end

ExceptionHandling.logger = LoggerStub.new

def dont_stub_log_error
  true
end

module TestHelper
  @constant_overrides = []
  class << self
    attr_accessor :constant_overrides
  end

  def setup_constant_overrides
    unless TestHelper.constant_overrides.nil? || TestHelper.constant_overrides.empty?
      raise "Uh-oh! constant_overrides left over: #{TestHelper.constant_overrides.inspect}"
    end

    Time.now_override = nil

    ExceptionHandling.environment           = 'not_test'
    ExceptionHandling.server_name           = 'server'
    ExceptionHandling.filter_list_filename    = "./config/exception_filters.yml"
  end

  def teardown_constant_overrides
    TestHelper.constant_overrides&.reverse&.each do |parent_module, k, v|
      ExceptionHandling.ensure_safe "constant cleanup #{k.inspect}, #{parent_module}(#{parent_module.class})::#{v.inspect}(#{v.class})" do
        silence_warnings do
          if v == :never_defined
            parent_module.send(:remove_const, k)
          else
            parent_module.const_set(k, v)
          end
        end
      end
    end
    TestHelper.constant_overrides = []
  end

  def set_test_const(const_name, value)
    const_name.is_a?(Symbol) and const_name = const_name.to_s
    const_name.is_a?(String) or raise "Pass the constant name, not its value!"

    final_parent_module = final_const_name = nil
    original_value =
      const_name.split('::').reduce(Object) do |parent_module, nested_const_name|
        parent_module == :never_defined and raise "You need to set each parent constant earlier! #{nested_const_name}"
        final_parent_module = parent_module
        final_const_name    = nested_const_name
        begin
          parent_module.const_get(nested_const_name)
        rescue
          :never_defined
        end
      end

    TestHelper.constant_overrides << [final_parent_module, final_const_name, original_value]

    silence_warnings { final_parent_module.const_set(final_const_name, value) }
  end
end

def assert_equal_with_diff(arg1, arg2, msg = '')
  if arg1 == arg2
    expect(true).to be_truthy # To keep the assertion count accurate
  else
    expect(arg1).to eq(arg2), "#{msg}\n#{Diff.compare(arg1, arg2)}"
  end
end

def require_test_helper(helper_path)
  require_relative "helpers/#{helper_path}"
end

class Time
  class << self
    attr_reader :now_override

    def now_override=(override_time)
      if override_time.is_a?(ActiveSupport::TimeWithZone)
        override_time = override_time.localtime
      else
        override_time.nil? || override_time.is_a?(Time) or raise "override_time should be a Time object, but was a #{override_time.class.name}"
      end
      @now_override = override_time
    end

    unless defined?(@@_old_now_defined)
      alias old_now now
      @@_old_now_defined = true
    end

    def now
      now_override ? now_override.dup : old_now
    end
  end
end

RSpec.configure do |config|
  config.add_formatter(RspecJunitFormatter, 'spec/reports/rspec.xml')
  config.include TestHelper

  config.before(:each) do
    setup_constant_overrides
    unless defined?(Rails) && defined?(Rails.env)
      module Rails
        class << self
          attr_writer :env

          def env
            @env ||= 'test'
          end
        end
      end
    end
  end

  config.after(:each) do
    teardown_constant_overrides
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.expect_with(:rspec, :test_unit)

  RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 2_000
end
