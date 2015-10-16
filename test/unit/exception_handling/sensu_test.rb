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

        assert_raise(RuntimeError, "Invalid alert level") do
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
        mock.any_instance_of(Addrinfo).connect.with_any_args { @socket }

        ExceptionHandling::Sensu.send_event(@event)

        assert_equal @event.to_json, @socket.sent.first
      end
    end
  end
end
