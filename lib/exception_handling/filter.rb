module ExceptionHandling

  class Filter
    MATCH_SECTIONS =  [:error, :request, :session, :environment, :backtrace, :event_response]


    def initialize(filter_name, regexes)
      @regexes = Hash[ regexes.map do |section_param, regex|
        section = section_param.to_sym
        section.in?( MATCH_SECTIONS ) or raise "Unknown section: #{section}"
        [section, (Regexp.new(regex, 'i') unless regex.blank?)]
      end ]

      raise "Filter #{filter_name} has all blank regexes: #{regexes.inspect}" if @regexes.all? { |section, regex| regex.nil? }
    end

    def match?(exception_data)
      @regexes.all? do |section, regex|
        regex.nil? ||
            case target = exception_data[section.to_s] || exception_data[section]
            when String
              regex =~ target
            when Array
              target.any? { |row| row =~ regex }
            when Hash
              target[:to_s] =~ regex
            when NilClass
              false
            else
              raise "Unexpected class #{exception_data[section].class.name}"
            end
      end
    end
  end
end
