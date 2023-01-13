# frozen_string_literal: true

module ExceptionHandling
  class HoneybadgerExceptionClassTagger
    # @param config [Hash]
    def initialize(config)
      config or raise ArgumentError, "config required for HoneybadgerExceptionClassTagger"

      @tags_by_exception_name = {}
      @tags_by_exception_class = {}

      config.each do |tag, names_and_classes|
        names_and_classes.each do |name_or_class|
          case name_or_class
          when String
            @tags_by_exception_name[name_or_class] ||= []
            @tags_by_exception_name[name_or_class] << tag
          else
            @tags_by_exception_class[name_or_class] ||= []
            @tags_by_exception_class[name_or_class] << tag
          end
        end
      end
    end

    # @param exception [ExceptionInfo]
    #
    # @return [Array<String>]
    def matching_tags(exception_info)
      exception = exception_info.exception
      matching_exception_name_tags(exception) + matching_exception_class_tags(exception)
    end

    private

    def matching_exception_name_tags(exception)
      @tags_by_exception_name[exception.class.name] || []
    end

    def matching_exception_class_tags(exception)
      @tags_by_exception_class[exception.class] || []
    end
  end
end
