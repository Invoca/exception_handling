# frozen_string_literal: true

require 'active_support'
require 'active_support/time'
require 'active_support/test_case'
require 'active_model'
require 'action_mailer'
require 'action_dispatch'
require 'hobo_support'
require 'shoulda'
require 'rr'
require 'minitest/autorun'
require 'pry'
require 'honeybadger'
require 'contextual_logger'

require 'exception_handling'
require 'exception_handling/testing'

ActiveSupport::TestCase.test_order = :sorted

class LoggerStub
  include ContextualLogger
  attr_accessor :logged

  def initialize
    clear
  end

  def info(message, **log_context)
    logged << { message: message, context: log_context }
  end

  def warn(message, **log_context)
    logged << { message: message, context: log_context }
  end

  def fatal(message, **log_context)
    logged << { message: message, context: log_context }
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

ActionMailer::Base.delivery_method = :test

_ = ActiveSupport
_ = ActiveSupport::TestCase

class ActiveSupport::TestCase
  @@constant_overrides = []

  setup do
    unless @@constant_overrides.nil? || @@constant_overrides.empty?
      raise "Uh-oh! constant_overrides left over: #{@@constant_overrides.inspect}"
    end

    unless defined?(Rails) && defined?(Rails.env)
      module ::Rails
        class << self
          attr_writer :env

          def env
            @env ||= 'test'
          end
        end
      end
    end

    Time.now_override = nil

    ActionMailer::Base.deliveries.clear

    ExceptionHandling.email_environment     = 'Test'
    ExceptionHandling.sender_address        = 'server@example.com'
    ExceptionHandling.exception_recipients  = 'exceptions@example.com'
    ExceptionHandling.escalation_recipients = 'escalation@example.com'
    ExceptionHandling.server_name           = 'server'
    ExceptionHandling.mailer_send_enabled     = true
    ExceptionHandling.filter_list_filename    = "./config/exception_filters.yml"
    ExceptionHandling.eventmachine_safe       = false
    ExceptionHandling.eventmachine_synchrony  = false
    ExceptionHandling.sensu_host              = "127.0.0.1"
    ExceptionHandling.sensu_port              = 3030
    ExceptionHandling.sensu_prefix            = ""
  end

  teardown do
    @@constant_overrides&.reverse&.each do |parent_module, k, v|
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
    @@constant_overrides = []
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

    @@constant_overrides << [final_parent_module, final_const_name, original_value]

    silence_warnings { final_parent_module.const_set(final_const_name, value) }
  end

  def assert_emails(expected, message = nil)
    if block_given?
      original_count = ActionMailer::Base.deliveries.size
      yield
    else
      original_count = 0
    end
    assert_equal expected, ActionMailer::Base.deliveries.size - original_count, "wrong number of emails#{': ' + message.to_s if message}"
  end
end

def assert_equal_with_diff(arg1, arg2, msg = '')
  if arg1 == arg2
    assert true # To keep the assertion count accurate
  else
    assert_equal arg1, arg2, "#{msg}\n#{Diff.compare(arg1, arg2)}"
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
