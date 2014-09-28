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

      should "allow matching of "

    end

  end
end
