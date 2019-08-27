# frozen_string_literal: true

require "socket"

module ExceptionHandling
  module Sensu
    LEVELS = {
      warning: 1,
      critical: 2
    }.freeze

    class << self
      def generate_event(name, message, level = :warning)
        status = LEVELS[level] or raise "Invalid alert level #{level}"

        event = { name: ExceptionHandling.sensu_prefix.to_s + name, output: message, status: status }

        send_event(event)
      end

      def send_event(event)
        Socket.tcp(ExceptionHandling.sensu_host, ExceptionHandling.sensu_port) do |sock|
          sock.send(event.to_json, 0)
        end
      end
    end
  end
end
