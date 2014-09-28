module ExceptionHandling
  class ExceptionFilters

    def initialize( filter_path )
      @filter_path = filter_path
      @filters = { }
      @filters_last_modified_time = nil
    end

    def filtered?( exception_data )
      refresh_filters

      @filters.any? do |name, filter|
        if ( match = filter.match?( exception_data ) )
          ExceptionHandling.logger.warn( "Filtered exception using '#{name}'; not sending email to notify" )
        end
        match
      end
    end

    private

    def refresh_filters
      mtime = last_modified_time
      if @filters_last_modified_time.nil? || mtime != @filters_last_modified_time
        ExceptionHandling.logger.info( "Reloading filter list from: #{@filter_path}.  Last loaded time: #{@filters_last_modified_time}. Last modified time: #{mtime}" )
        @filters_last_modified_time = mtime # make race condition fall on the side of reloading unnecessarily next time rather than missing a set of changes

        @filters = load_file
      end

    rescue => ex # any exceptions
      ExceptionHandling::log_error( ex, "ExceptionRegexes::refresh_filters: #{@filter_path}", nil, true)
    end

    def load_file
      # store all strings from YAML file into regex's on initial load, instead of converting to regex on every exception that is logged
      filters = YAML::load_file( @filter_path )
      Hash[ filters.map do |filter_name, regexes|
        [filter_name, Filter.new( filter_name, regexes )]
      end ]
    end

    def last_modified_time
      File.mtime( @filter_path )
    end
  end
end
