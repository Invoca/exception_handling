require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class ExceptionFiltersTest < ActiveSupport::TestCase

    context "With stubbed yaml content" do
      setup do
        filter_list = { :exception1 => { error: "my error message" },
                        :exception2 => { error: "some other message", session: "misc data" } }
        stub(YAML).load_file { filter_list }

        # bump modified time up to get the above filter loaded
        stub(File).mtime { incrementing_mtime }
      end

      should "load the filter data" do
        stub(File).mtime { incrementing_mtime }
        @exception_filters = ExceptionFilters.new( ExceptionHandling.filter_list_filename )
        assert_nothing_raised "Loading the exception filter should not raise" do
          @exception_filters.send :load_file
        end
        assert !@exception_filters.filtered?( error: "Scott says unlikely to ever match" )

      end
    end

    context "with live yaml content" do
      setup do
        @filename = File.expand_path('../../../fixtures/sample_exception_filters.yml',  __FILE__)
        @exception_filters = ExceptionFilters.new( @filename )
        assert_nothing_raised "Loading the exception filter should not raise" do
          @exception_filters.send :load_file
        end
      end

      should "load the filter data" do
        assert !@exception_filters.filtered?( error: "Scott says unlikely to ever match" )
      end


    end
  end
end
