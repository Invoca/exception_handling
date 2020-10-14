# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)

module ExceptionHandling
  describe ExceptionDescription do

    context "Filter" do
      it "allow direct matching of strings" do
        @f = ExceptionDescription.new(:filter1, error: "my error message")
        expect(@f.match?('error' => "my error message")).to be_truthy
      end

      it "allow direct matching of strings on with symbol keys" do
        @f = ExceptionDescription.new(:filter1, error: "my error message")
        expect(@f.match?(error: "my error message")).to be_truthy
      end

      it "allow wildcards to cross line boundries" do
        @f = ExceptionDescription.new(:filter1, error: "my error message.*with multiple lines")
        expect(@f.match?(error: "my error message\nwith more than one, with multiple lines")).to be_truthy
      end

      it "complain when no regexps have a value" do
        expect { ExceptionDescription.new(:filter1, error: nil) }.to raise_exception(ArgumentError, /has all blank regexes/)
      end

      it "report when an invalid key is passed" do
        expect { ExceptionDescription.new(:filter1, error: "my error message", not_a_parameter: false) }.to raise_exception(ArgumentError, "Unknown section: not_a_parameter")
      end

      it "allow send_to_honeybadger to be specified and have it disabled by default" do
        expect(!ExceptionDescription.new(:filter1, error: "my error message", send_to_honeybadger: false).send_to_honeybadger).to be_truthy
        expect(ExceptionDescription.new(:filter1, error: "my error message", send_to_honeybadger: true).send_to_honeybadger).to be_truthy
        expect(!ExceptionDescription.new(:filter1, error: "my error message").send_to_honeybadger).to be_truthy
      end

      it "allow send_metric to be configured" do
        expect(!ExceptionDescription.new(:filter1, error: "my error message", send_metric: false).send_metric).to be_truthy
        expect(ExceptionDescription.new(:filter1, error: "my error message").send_metric).to be_truthy
      end

      it "provide metric name" do
        expect(ExceptionDescription.new(:filter1, error: "my error message").metric_name).to eq("filter1")
        expect(ExceptionDescription.new(:filter1, error: "my error message", metric_name: :some_other_metric_name).metric_name).to eq("some_other_metric_name")
      end

      it "replace spaces in metric name" do
        @f = ExceptionDescription.new(:"filter has spaces", error: "my error message")
        expect(@f.metric_name).to eq( "filter_has_spaces")
      end

      it "allow notes to be recorded" do
        expect(ExceptionDescription.new(:filter1, error: "my error message").notes).to be_nil
        expect(ExceptionDescription.new(:filter1, error: "my error message", notes: "a long string").notes).to eq("a long string")
      end

      it "not consider config options in the filter set" do
        expect(ExceptionDescription.new(:filter1, error: "my error message", send_metric: false).match?(error: "my error message")).to be_truthy
        expect(ExceptionDescription.new(:filter1, error: "my error message", metric_name: "false").match?(error: "my error message")).to be_truthy
        expect(ExceptionDescription.new(:filter1, error: "my error message", notes: "hey").match?(error: "my error message")).to be_truthy
      end

      it "provide exception details" do
        exception_description = ExceptionDescription.new(:filter1, error: "my error message", notes: "hey")

        expected = { "send_metric" => true, "metric_name" => "filter1", "notes" => "hey" }

        expect(exception_description.exception_data).to eq( expected)
      end

      it "match multiple email addresses" do
        mobi = "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for 'mcc@mobistreak.com'"
        credit = "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for 'damon@thecreditpros.com'"

        exception_description = ExceptionDescription.new(:filter1, error: "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for '(mcc\@mobistreak|damon\@thecreditpros).com'")
        expect(exception_description.match?(error: mobi)).to be_truthy
        expect(exception_description.match?(error: credit)).to be_truthy
      end
    end
  end
end
