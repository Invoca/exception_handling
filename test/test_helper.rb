require 'active_support'
require 'active_support/time'
require 'active_support/test_case'
require 'action_mailer'
require 'shoulda'
require 'mocha/setup'
require 'test/mocha_patch'

ActionMailer::Base.delivery_method = :test

_ = ActiveSupport
_ = ActiveSupport::TestCase

class ActiveSupport::TestCase
  @@constant_overrides = []

  setup do
    unless @@constant_overrides.nil? || @@constant_overrides.empty?
      raise "Uh-oh! constant_overrides left over: #{@@constant_overrides.inspect}"
    end
  end

  teardown do
    @@constant_overrides && @@constant_overrides.reverse.each do |parent_module, k, v|
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
        parent_module.const_get(nested_const_name) rescue :never_defined
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
    assert_equal expected, ActionMailer::Base.deliveries.size - original_count, "wrong number of emails#{ ': ' + message.to_s if message}"
  end
end

class Time
  class << self
    attr_reader :now_override

    def now_override= override_time
      if ActiveSupport::TimeWithZone === override_time
        override_time = override_time.localtime
      else
        override_time.nil? || Time === override_time or raise "override_time should be a Time object, but was a #{override_time.class.name}"
      end
      @@now_override = override_time
    end

    unless defined? @@_old_now_defined
      alias old_now now
      @@_old_now_defined = true
    end
  end

  def self.now
    now_override ? now_override.dup : old_now
  end
end
