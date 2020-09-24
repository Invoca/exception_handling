# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)

module ExceptionHandling
  describe ExceptionCatalog do

    context "With stubbed yaml content" do
      before do
        filter_list = { exception1: { error: "my error message" },
                        exception2: { error: "some other message", session: "misc data" } }
        allow(YAML).to receive(:load_file) { filter_list }

        # bump modified time up to get the above filter loaded
        allow(File).to receive(:mtime) { incrementing_mtime }
      end

      context "with loaded data" do
        before do
          allow(File).to receive(:mtime) { incrementing_mtime }
          @exception_catalog = ExceptionCatalog.new(ExceptionHandling.filter_list_filename)
          @exception_catalog.send :load_file
        end

        it "have loaded filters" do
          expect(@exception_catalog.instance_eval("@filters").size).to eq(2)
        end

        it "find messages in the catalog" do
          expect(!@exception_catalog.find(error: "Scott says unlikely to ever match")).to be_truthy
        end

        it "find matching data" do
          exception_description = @exception_catalog.find(error: "this is my error message, which should match something")
          expect(exception_description).to be_truthy
          expect(exception_description.filter_name).to eq(:exception1)
        end
      end

      it "write errors loading the yaml file directly to the log file" do
        @exception_catalog = ExceptionCatalog.new(ExceptionHandling.filter_list_filename)

        expect(ExceptionHandling).to receive(:log_error).never
        expect(ExceptionHandling).to receive(:write_exception_to_log).with(anything, "ExceptionCatalog#refresh_filters: ./config/exception_filters.yml", anything)
        expect(@exception_catalog).to receive(:load_file) { raise "noooooo" }

        @exception_catalog.find({})
      end
    end

    context "with live yaml content" do
      before do
        @filename = File.expand_path('../../../config/exception_filters.yml',  __dir__)
        @exception_catalog = ExceptionCatalog.new(@filename)
        expect do
          @exception_catalog.send :load_file
        end.not_to raise_error
      end

      it "load the filter data" do
        expect(!@exception_catalog.find(error: "Scott says unlikely to ever match")).to be_truthy
        expect(!@exception_catalog.find(error: "Scott says unlikely to ever match")).to be_truthy
      end
    end

    context "with no yaml content" do
      before do
        @exception_catalog = ExceptionCatalog.new(nil)
      end

      it "not load filter data" do
        expect(ExceptionHandling).to receive(:write_exception_to_log).with(any_args).never
        @exception_catalog.find(error: "Scott says unlikely to ever match")
      end
    end

    private

    def incrementing_mtime
      @mtime ||= Time.now
      @mtime += 1.day
    end

  end
end
