require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class HoneybadgerCallbacksTest < ActiveSupport::TestCase

    class HoneybadgerStub
      def self.local_variable_filter(&block)
        @local_variable_filter = Proc.new if block_given?
        @local_variable_filter
      end

      def self.call_local_variable_filter(symbol, object, filter_keys)
        @local_variable_filter.call(symbol, object, filter_keys)
      end
    end

    class TestPoroWithAttribute
      attr_reader :test_attribute

      def initialize
        @test_attribute = 'test'
      end
    end

    class TestPoroWithFilteredAttribute
      attr_reader :password

      def initialize
        @password = 'secret'
      end
    end

    class TestPoroWithFilteredAttributeAndId < TestPoroWithFilteredAttribute
      attr_reader :id

      def initialize
        super
        @id = 1
      end
    end

    class TestPoroWithFilteredAttributePkAndId < TestPoroWithFilteredAttributeAndId
      def to_pk
        'TestPoroWithFilteredAttributePkAndId_1'
      end
    end

    context "register_callbacks" do
      setup do
        stub(ExceptionHandling).honeybadger? { true }
        ExceptionHandling.const_set('Honeybadger', HoneybadgerStub)
      end

      teardown do
        ExceptionHandling.send(:remove_const, 'Honeybadger')
      end

      should "store the callbacks in the honeybadger object" do
        HoneybadgerCallbacks.register_callbacks
        result = HoneybadgerStub.call_local_variable_filter(:variable_name, 'test', [])
        assert_equal('test', result)
      end
    end

    context "local_variable_filter" do
      should "not inspect String, Hash, Array, Set, Numeric, TrueClass, FalseClass, NilClass" do
        [
          ['test', String],
          [{a: 1}, Hash],
          [[1,2], Array],
          [Set.new([1,2]), Set],
          [4.5, Numeric],
          [true, TrueClass],
          [false, FalseClass],
          [nil, NilClass]
        ].each do |object, expected_class|
          result = HoneybadgerCallbacks.local_variable_filter(:variable_name, object, [])
          assert result.is_a?(expected_class), "Expected #{expected_class.name} but got #{result.class.name}"
        end
      end

      should "inspect other classes" do
        result = HoneybadgerCallbacks.local_variable_filter(:variable_name, TestPoroWithAttribute.new, ['password'])
        assert_match(/#<ExceptionHandling::HoneybadgerCallbacksTest::TestPoroWithAttribute:.* @test_attribute="test">/, result)
      end

      context "not inspect objects that contain filter keys" do
        should "use to_pk if available, even if id is available" do
          result = HoneybadgerCallbacks.local_variable_filter(:variable_name, TestPoroWithFilteredAttributePkAndId.new, ['password'])
          assert_match(/#<ExceptionHandling::HoneybadgerCallbacksTest::TestPoroWithFilteredAttributePkAndId @pk=TestPoroWithFilteredAttributePkAndId_1, \[FILTERED\]>/, result)
        end

        should "use id if to_pk is not available" do
          result = HoneybadgerCallbacks.local_variable_filter(:variable_name, TestPoroWithFilteredAttributeAndId.new, ['password'])
          assert_match(/#<ExceptionHandling::HoneybadgerCallbacksTest::TestPoroWithFilteredAttributeAndId @id=1, \[FILTERED\]>/, result)
        end

        should "print the object name if no id or to_pk" do
          result = HoneybadgerCallbacks.local_variable_filter(:variable_name, TestPoroWithFilteredAttribute.new, ['password'])
          assert_match(/#<ExceptionHandling::HoneybadgerCallbacksTest::TestPoroWithFilteredAttribute \[FILTERED\]>/, result)
        end
      end
    end
  end
end