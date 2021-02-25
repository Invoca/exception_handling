# frozen_string_literal: true

require 'escalate'

module ExceptionHandling
  module EscalateCallback
    class << self
      def register!
        Escalate.on_escalate(log_first: false) do |exception, location_message, **context|
          ::ExceptionHandling.log_error(exception, location_message, **context)
        end
      end
    end
  end
end
