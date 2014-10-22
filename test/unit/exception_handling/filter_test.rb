require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class FilterTest < ActiveSupport::TestCase

    context "Filter" do

      should "allow direct matching of strings" do
        @f = Filter.new(:filter1, :error => "my error message" )
        assert @f.match?( 'error' => "my error message")
      end

      should "allow direct matching of strings on with symbol keys" do
        @f = Filter.new(:filter1, :error => "my error message" )
        assert @f.match?( :error => "my error message")
      end

      should "complain when no regexps have a value" do
        assert_raise(ArgumentError, "has all blank regexe") { Filter.new(:filter1, error: nil) }
      end

      should "report when an invalid key is passed" do
        assert_raise(ArgumentError, "Unknown section: not_a_parameter") { Filter.new(:filter1, error: "my error message", not_a_parameter: false) }
      end

      should "allow send email to be specified" do
        assert !Filter.new(:filter1, error: "my error message", send_email: false ).send_email
        assert Filter.new(:filter1, error: "my error message", send_email: true ).send_email
        assert !Filter.new(:filter1, error: "my error message" ).send_email
      end

      should "allow send_metric to be configured" do
        assert !Filter.new(:filter1, error: "my error message", send_metric: false ).send_metric
        assert Filter.new(:filter1, error: "my error message", send_email: true ).send_metric
        assert Filter.new(:filter1, error: "my error message" ).send_metric
      end

      should "provide metric name" do
        assert_equal "filter1", Filter.new(:filter1, error: "my error message" ).metric_name
        assert_equal "some_other_metric_name", Filter.new(:filter1, error: "my error message", metric_name: :some_other_metric_name ).metric_name
      end

      should "allow notes to be recorded" do
        assert_equal nil, Filter.new(:filter1, error: "my error message" ).notes
        assert_equal "a long string", Filter.new(:filter1, error: "my error message", notes: "a long string" ).notes
      end

      should "not consider config options in the filter set" do
        assert Filter.new(:filter1, error: "my error message", send_email: false ).match?( :error => "my error message")
        assert Filter.new(:filter1, error: "my error message", send_metric: false ).match?( :error => "my error message")
        assert Filter.new(:filter1, error: "my error message", metric_name: "false" ).match?( :error => "my error message")
        assert Filter.new(:filter1, error: "my error message", notes: "hey" ).match?( :error => "my error message")
      end

    end

  end
end
