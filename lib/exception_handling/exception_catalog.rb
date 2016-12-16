module ExceptionHandling
  class ExceptionCatalog

    def initialize(filter_path)
      @filter_path = filter_path
      @filters = { }
      @filters_last_modified_time = nil
    end

    def find(exception_data)
      refresh_filters
      @filters.values.find { |filter|  filter.match?(exception_data) }
    end

    private

    def refresh_filters
      mtime = last_modified_time
      if @filters_last_modified_time.nil? || mtime != @filters_last_modified_time
        ExceptionHandling.logger.info("Reloading filter list from: #{@filter_path}.  Last loaded time: #{@filters_last_modified_time}. Last modified time: #{mtime}")
        load_file
      end

    rescue => ex # any exceptions
      # DO NOT CALL ExceptionHandling.log_error because this method is called from that.  It can loop and cause mayhem.
      ExceptionHandling.write_exception_to_log(ex, "ExceptionRegexes::refresh_filters: #{@filter_path}", Time.now.to_i)
    end

    def load_file
      @filters_last_modified_time = last_modified_time # make race condition fall on the side of reloading unnecessarily next time rather than missing a set of changes

      filters = YAML::load_file(@filter_path)
      filter_hash_values = filters.map { |filter_name, regexes|  [filter_name.to_sym, ExceptionDescription.new(filter_name.to_sym, regexes.symbolize_keys)] }
      @filters = Hash[ filter_hash_values ]
    end

    def last_modified_time
      File.mtime(@filter_path)
    end
  end
end
