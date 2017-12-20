require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class ExceptionCatalogTest < ActiveSupport::TestCase

    context "With stubbed yaml content" do
      setup do
        filter_list = { :exception1 => { error: "my error message" },
                        :exception2 => { error: "some other message", session: "misc data" } }
        stub(YAML).load_file { filter_list }

        # bump modified time up to get the above filter loaded
        stub(File).mtime { incrementing_mtime }
      end

      context "with loaded data" do
        setup do
          stub(File).mtime { incrementing_mtime }
          @exception_catalog = ExceptionCatalog.new( ExceptionHandling.filter_list_filename )
          @exception_catalog.send :load_file
        end

        should "have loaded filters" do
          assert_equal 2, @exception_catalog.instance_eval("@filters").size
        end

        should "find messages in the catalog" do
          assert !@exception_catalog.find( error: "Scott says unlikely to ever match" )
        end

        should "find matching data" do
          exception_description = @exception_catalog.find(error: "this is my error message, which should match something")
          assert exception_description
          assert_equal :exception1, exception_description.filter_name
        end
      end

      should "write errors loading the yaml file directly to the log file" do
        @exception_catalog = ExceptionCatalog.new( ExceptionHandling.filter_list_filename )

        mock(ExceptionHandling).log_error.never
        mock(ExceptionHandling).write_exception_to_log(anything(), "ExceptionCatalog#refresh_filters: ./config/exception_filters.yml", anything())
        mock(@exception_catalog).load_file { raise "noooooo"}

        @exception_catalog.find({})
      end

    end

    context "with live yaml content" do
      setup do
        @filename = File.expand_path('../../../../config/exception_filters.yml',  __FILE__)
        @exception_catalog = ExceptionCatalog.new( @filename )
        assert_nothing_raised "Loading the exception filter should not raise" do
          @exception_catalog.send :load_file
        end
      end

      should "load the filter data" do
        assert !@exception_catalog.find( error: "Scott says unlikely to ever match" )
        assert !@exception_catalog.find( error: "Scott says unlikely to ever match" )
      end
    end

    context "with no yaml content" do
      setup do
        @exception_catalog = ExceptionCatalog.new(nil)
      end

      should "not load filter data" do
        mock(ExceptionHandling).write_exception_to_log.with_any_args.never
        @exception_catalog.find( error: "Scott says unlikely to ever match" )
      end
    end

    private

    def incrementing_mtime
      @mtime ||= Time.now
      @mtime += 1.day
    end

  end
end
