# frozen_string_literal: true

module ExceptionHandling
  class HoneybadgerFilepathTagger

    VERSIONING_PATTERN = /\d+\.\d+\.\d+(\.\d+)?/.freeze

    GEM_FILEPATH_PATTERNS = [
      /\(#{VERSIONING_PATTERN}\) lib\//,            # Example: activerecord (5.2.8.1) lib/active_record/relation/batches.rb:70:in `block (2 levels) in find_each'" # rubocop:disable Layout/LineLength
      /\/#{VERSIONING_PATTERN}\/lib\/ruby\/gems\//, # Example: "/Users/orabani/.rbenv/versions/2.7.5/lib/ruby/gems/2.7.0/gems/rspec-core-3.9.2/lib/rspec/core/reporter.rb" # rubocop:disable Layout/LineLength
      /bundle\/ruby\/#{VERSIONING_PATTERN}\/gems/,  # Example: "bundle/ruby/2.7.0/gems/exceptional_synchrony-1.4.4/lib/exceptional_synchrony/event_machine_proxy.rb:58:in `block (2 levels) in next_tick'" # rubocop:disable Layout/LineLength
      /versions\/#{VERSIONING_PATTERN}\/bin/,       # Example: "/Users/orabani/.rbenv/versions/2.7.5/bin/rspec"
      /^\(eval\)/,                                  # Example: "(eval):1:in `block (2 levels) in perform'"
      /^\/usr\/local\/lib\/ruby/                    # Example: "/usr/local/lib/ruby/2.7.0/benchmark.rb:308:in `realtime'"
    ].freeze

    # @param config [Hash]
    def initialize(config)
      config or raise ArgumentError, "config required for HoneybadgerFilepathTagger"

      @tags_by_filepath =
        config.reduce({}) do |tags_by_path, (label, filepaths)|
          filepaths.each do |filepath|
            tags_by_path[filepath] ||= []
            tags_by_path[filepath] << label
          end
          tags_by_path
        end
    end

    # @param exception_info [ExceptionInfo]
    #
    # @return [Array<String>]
    def matching_tags(exception_info)
      exception_info.is_a?(ExceptionInfo) or raise ArgumentError, "Expected ExceptionInfo object, received #{exception_info.inspect}"
      if (backtrace = exception_info.enhanced_data[:backtrace])
        matching_tags_for_backtrace(backtrace)
      else
        []
      end
    end

    private

    def matching_tags_for_backtrace(backtrace)
      pruned_backtrace = prune_line_numbers(backtrace).uniq
      cleaned_backtrace = reject_gem_filepaths(pruned_backtrace)
      # Find the matching full filepaths first so that when we look for tags we need to iterate over fewer results.
      matching_full_filepaths = cleaned_backtrace.grep(Regexp.union(*@tags_by_filepath.keys))
      tags_for_matching_full_filepaths(matching_full_filepaths)
    end

    # Prune line numbers and method names from backtrace entries.
    # @param backtrace [Array<String>]
    #
    # @return [Array<String>]
    def prune_line_numbers(backtrace)
      backtrace.map { _1.gsub(/:\d+:in.*/, "") }
    end

    def reject_gem_filepaths(backtrace)
      backtrace.reject { _1.match?(Regexp.union(*GEM_FILEPATH_PATTERNS)) }
    end

    # @param matching_full_filepath [Array<String>] An array of matching full file paths from the backtrace
    #
    # @return [Array<String>] the tags the match those full file paths
    def tags_for_matching_full_filepaths(matching_full_filepaths)
      matching_full_filepaths.map do |matching_full_filepath|
        @tags_by_filepath.map_compact do |filepath, tags|
          if matching_full_filepath.match?(filepath)
            tags
          end
        end
      end.flatten.uniq
    end
  end
end
