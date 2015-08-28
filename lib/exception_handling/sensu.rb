require "socket"

module ExceptionHandling
  module Sensu
    LEVELS = {
        warning:  1,
        critical: 2
    }

    class << self
      def generate_event(name, message, level = :warning)
        status = LEVELS[level] or raise "Invalid alert level #{level}"

        event = {name: ExceptionHandling.sensu_prefix + name, output: message, status: status}

        send_event(event)
      end

      def send_event(event)
        s = TCPSocket.new(ExceptionHandling.sensu_host, ExceptionHandling.sensu_port)
        s.send(event.to_json, 0)
        s.close
      end
    end
  end
end