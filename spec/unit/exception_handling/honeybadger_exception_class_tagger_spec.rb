# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)

class ExampleStringNamedError < StandardError; end
class AdditionalExampleError < StandardError; end

module ExceptionHandling
  describe HoneybadgerExceptionClassTagger do
    def exception_info(exception)
      ExceptionInfo.new(exception, nil, Time.now.to_i)
    end

    subject { HoneybadgerExceptionClassTagger.new(config_hash) }

    context "without config_hash" do
      let(:config_hash) { nil }

      it "raises an ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, "config required for HoneybadgerExceptionClassTagger")
      end
    end

    context "#matching_tags" do
      let(:config_hash) do
        {
          "cereals" => [ # Example showing that the labels can be arbitrary
            "CaptainCrunchException",
            "CocoaPuffsException",
            ExampleStringNamedError
          ],
          "ivr-campaigns-team" => [
            "SomeOtherErrorClass",
            "RuntimeError"
          ],
          "calls-team" => [
            "SomeCallsSpecificException",
            "ExampleStringNamedError",
            RuntimeError
          ]
        }
      end

      it "returns tags for matching exception class names" do
        exception = nil
        begin
          raise ExampleStringNamedError, "Here's an error!"
        rescue => ex
          exception = ex
        end
        expect(subject.matching_tags(exception_info(exception))).to match_array(["calls-team", "cereals"])
      end

      it "returns tags for matching exception classes" do
        exception = nil
        begin
          raise "Here's a runtime error!"
        rescue => ex
          exception = ex
        end
        expect(subject.matching_tags(exception_info(exception))).to match_array(["ivr-campaigns-team", "calls-team"])
      end

      it "returns empty array for exception classes that are not matching" do
        exception = nil
        begin
          raise AdditionalExampleError, "Here's an error!"
        rescue => ex
          exception = ex
        end
        expect(subject.matching_tags(exception_info(exception))).to match_array([])
      end
    end
  end
end
