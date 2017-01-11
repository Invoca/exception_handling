module ExceptionHandling
  class ExceptionDescription
    MATCH_SECTIONS =  [:error, :request, :session, :environment, :backtrace, :event_response]

    CONFIGURATION_SECTIONS = {
        send_email:           false,  # should email be sent?
        send_to_honeybadger:  true,   # should be sent to honeybadger?
        send_metric:          true,   # should the metric be sent.
        metric_name:          nil,    # Will be derived from section name if not passed
        notes:                nil     # Will be included in exception email if set, used to keep notes and relevant links
    }

    attr_reader :filter_name, :send_email, :send_to_honeybadger, :send_metric, :metric_name, :notes

    def initialize(filter_name, configuration)
      @filter_name = filter_name

      invalid_sections = configuration.except(*(CONFIGURATION_SECTIONS.keys + MATCH_SECTIONS))
      invalid_sections.empty? or raise ArgumentError, "Unknown section: #{invalid_sections.keys.join(",")}"

      @configuration = CONFIGURATION_SECTIONS.merge(configuration)
      @send_email  = @configuration[:send_email]
      @send_to_honeybadger = @configuration[:send_to_honeybadger]
      @send_metric = @configuration[:send_metric]
      @metric_name = (@configuration[:metric_name] || @filter_name ).to_s.gsub(" ","_")
      @notes       = @configuration[:notes]

      regex_config = @configuration.reject { |k,v| k.in?(CONFIGURATION_SECTIONS.keys) || v.blank? }

      @regexes = Hash[regex_config.map { |section, regex| [section, Regexp.new(regex, 'i') ] }]

      !@regexes.empty? or raise ArgumentError, "Filter #{filter_name} has all blank regexes: #{configuration.inspect}"
    end

    def exception_data
      {
          "send_metric" => send_metric,
          "metric_name" => metric_name,
          "notes"       => notes
      }
    end

    def match?(exception_data)
      @regexes.all? do |section, regex|
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
