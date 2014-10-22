require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class FilterTest < ActiveSupport::TestCase

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

    end

  end
end
