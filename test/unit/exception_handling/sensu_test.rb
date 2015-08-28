require File.expand_path('../../../test_helper',  __FILE__)

module ExceptionHandling
  class SensuTest < ActiveSupport::TestCase
    context "#generate_event" do
      should "create an event" do
        mock(ExceptionHandling::Sensu).send_event({ name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1 })

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye")
      end

      should "add the sensu prefix" do
        ExceptionHandling.sensu_prefix = "cnn_"

        mock(ExceptionHandling::Sensu).send_event({ name: "cnn_world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1 })

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye")
      end

      should "allow the level to be set to critical" do
        mock(ExceptionHandling::Sensu).send_event({ name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 2 })

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye", :critical)
      end

      should "error if an invalid level is supplied" do
        dont_allow(ExceptionHandling::Sensu).send_event

        assert_raise RuntimeError do
          ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye", :hair_on_fire)
        end
      end
    end

    context "#send_event" do
      setup do
        @event = { name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1 }
        @socket = SocketStub.new
      end

      should "send event json to sensu client" do
        mock(TCPSocket).new("127.0.0.1", 3030) { @socket }

        ExceptionHandling::Sensu.send_event(@event)

        assert_equal @event.to_json, @socket.sent.first
      end

      should "close the socket after sending" do
        mock(TCPSocket).new("127.0.0.1", 3030) { @socket }

        ExceptionHandling::Sensu.send_event(@event)

        assert_equal false, @socket.connected
      end
    end
  end
end
