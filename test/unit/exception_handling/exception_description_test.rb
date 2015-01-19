require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class ExceptionDescriptionTest < ActiveSupport::TestCase

    context "Filter" do

      should "allow direct matching of strings" do
        @f = ExceptionDescription.new(:filter1, :error => "my error message" )
        assert @f.match?( 'error' => "my error message")
      end

      should "allow direct matching of strings on with symbol keys" do
        @f = ExceptionDescription.new(:filter1, :error => "my error message" )
        assert @f.match?( :error => "my error message")
      end

      should "complain when no regexps have a value" do
        assert_raise(ArgumentError, "has all blank regexe") { ExceptionDescription.new(:filter1, error: nil) }
      end

      should "report when an invalid key is passed" do
        assert_raise(ArgumentError, "Unknown section: not_a_parameter") { ExceptionDescription.new(:filter1, error: "my error message", not_a_parameter: false) }
      end

      should "allow send email to be specified" do
        assert !ExceptionDescription.new(:filter1, error: "my error message", send_email: false ).send_email
        assert ExceptionDescription.new(:filter1, error: "my error message", send_email: true ).send_email
        assert !ExceptionDescription.new(:filter1, error: "my error message" ).send_email
      end

      should "allow send_metric to be configured" do
        assert !ExceptionDescription.new(:filter1, error: "my error message", send_metric: false ).send_metric
        assert ExceptionDescription.new(:filter1, error: "my error message", send_email: true ).send_metric
        assert ExceptionDescription.new(:filter1, error: "my error message" ).send_metric
      end

      should "provide metric name" do
        assert_equal "filter1", ExceptionDescription.new(:filter1, error: "my error message" ).metric_name
        assert_equal "some_other_metric_name", ExceptionDescription.new(:filter1, error: "my error message", metric_name: :some_other_metric_name ).metric_name
      end

      should "replace spaces in metric name" do
        @f = ExceptionDescription.new(:"filter has spaces", :error => "my error message" )
        assert_equal "filter_has_spaces", @f.metric_name
      end

      should "allow notes to be recorded" do
        assert_equal nil, ExceptionDescription.new(:filter1, error: "my error message" ).notes
        assert_equal "a long string", ExceptionDescription.new(:filter1, error: "my error message", notes: "a long string" ).notes
      end

      should "not consider config options in the filter set" do
        assert ExceptionDescription.new(:filter1, error: "my error message", send_email: false ).match?( :error => "my error message")
        assert ExceptionDescription.new(:filter1, error: "my error message", send_metric: false ).match?( :error => "my error message")
        assert ExceptionDescription.new(:filter1, error: "my error message", metric_name: "false" ).match?( :error => "my error message")
        assert ExceptionDescription.new(:filter1, error: "my error message", notes: "hey" ).match?( :error => "my error message")
      end

      should "provide exception details" do
        exception_description = ExceptionDescription.new(:filter1, error: "my error message", notes: "hey" )

        expected = {"send_metric" => true, "metric_name" => "filter1", "notes" => "hey"}

        assert_equal expected, exception_description.exception_data
      end

      should "match multiple email addresses" do
        mobi = "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for 'mcc@mobistreak.com'"
        credit = "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for 'damon@thecreditpros.com'"

        exception_description = ExceptionDescription.new(:filter1, error: "ExceptionHandling::Warning: LoginAttempt::IPAddressLocked: failed login for '(mcc\@mobistreak|damon\@thecreditpros).com'" )
        assert exception_description.match?(error: mobi), "does not match mobi"
        assert exception_description.match?(error: credit), "does not match credit"
      end

    end

  end
end
