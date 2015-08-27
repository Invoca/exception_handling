require "socket"

module ExceptionHandling
  class Sensu
    class << self
      def generate_event(name, message, level = :warning)
        status = case level
                   when :warning
                     1
                   when :critical
                     2
                   else
                     raise "Invalid alert level #{level.to_s}"
                 end

        event = {name: "#{ExceptionHandling.sensu_prefix}#{name}", output: message, status: status}

        send_event(event)
      end

      def send_event(event)
        s = TCPSocket.new(ExceptionHandling.sensu_host, ExceptionHandling.sensu_port)
        s.send(event.to_json, 0)
      ensure
        s.close
      end
    end
  end
end