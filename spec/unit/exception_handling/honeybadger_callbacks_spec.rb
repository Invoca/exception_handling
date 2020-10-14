# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)

module ExceptionHandling
  describe HoneybadgerCallbacks do

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

    class TestRaiseOnInspect < TestPoroWithAttribute
      def inspect
        raise "some error"
      end
    end

    class TestRaiseOnInspectWithId < TestRaiseOnInspect
      def id
        123
      end
    end

    class TestRaiseOnInspectWithToPk < TestRaiseOnInspect
      def to_pk
        "SomeRecord-123"
      end
    end

    context "register_callbacks" do
      it "store the callbacks in the honeybadger object" do
        HoneybadgerCallbacks.register_callbacks
        result = Honeybadger.config.local_variable_filter.call(:variable_name, 'test', [])
        expect(result).to eq('test')
      end
    end

    context "local_variable_filter" do
      it "not inspect String, Hash, Array, Set, Numeric, TrueClass, FalseClass, NilClass" do
        [
          ['test', String],
          [{ a: 1 }, Hash],
          [[1, 2], Array],
          [Set.new([1, 2]), Set],
          [4.5, Numeric],
          [true, TrueClass],
          [false, FalseClass],
          [nil, NilClass]
        ].each do |object, expected_class|
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, object, [])
          expect(result.is_a?(expected_class)).to be_truthy
        end
      end

      it "inspect other classes" do
        result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestPoroWithAttribute.new, ['password'])
        expect(result).to match(/#<ExceptionHandling::TestPoroWithAttribute:.* @test_attribute="test">/)
      end

      context "when inspect raises exceptions" do
        it "handle exceptions for objects" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestRaiseOnInspect.new, ['password'])
          expect(result).to eq("#<ExceptionHandling::TestRaiseOnInspect [error 'RuntimeError: some error' while calling #inspect]>")
        end

        it "handle exceptions for objects responding to id" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestRaiseOnInspectWithId.new, ['password'])
          expect(result).to eq("#<ExceptionHandling::TestRaiseOnInspectWithId @id=123 [error 'RuntimeError: some error' while calling #inspect]>")
        end

        it "handle exceptions for objects responding to to_pk" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestRaiseOnInspectWithToPk.new, ['password'])
          expect(result).to eq("#<ExceptionHandling::TestRaiseOnInspectWithToPk @pk=SomeRecord-123 [error 'RuntimeError: some error' while calling #inspect]>")
        end
      end

      context "not inspect objects that contain filter keys" do
        it "use to_pk if available, even if id is available" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestPoroWithFilteredAttributePkAndId.new, ['password'])
          expect(result).to match(/#<ExceptionHandling::TestPoroWithFilteredAttributePkAndId @pk=TestPoroWithFilteredAttributePkAndId_1, \[FILTERED\]>/)
        end

        it "use id if to_pk is not available" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestPoroWithFilteredAttributeAndId.new, ['password'])
          expect(result).to match(/#<ExceptionHandling::TestPoroWithFilteredAttributeAndId @id=1, \[FILTERED\]>/)
        end

        it "print the object name if no id or to_pk" do
          result = HoneybadgerCallbacks.send(:local_variable_filter, :variable_name, TestPoroWithFilteredAttribute.new, ['password'])
          expect(result).to match(/#<ExceptionHandling::TestPoroWithFilteredAttribute \[FILTERED\]>/)
        end
      end
    end
  end
end
