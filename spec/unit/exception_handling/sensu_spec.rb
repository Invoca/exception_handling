# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)

module ExceptionHandling
  describe Sensu do
    context "#generate_event" do
      it "create an event" do
        expect(ExceptionHandling::Sensu).to receive(:send_event).with(name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1)

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye")
      end

      it "add the sensu prefix" do
        ExceptionHandling.sensu_prefix = "cnn_"

        expect(ExceptionHandling::Sensu).to receive(:send_event).with(name: "cnn_world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1)

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye")
      end

      it "allow the level to be set to critical" do
        expect(ExceptionHandling::Sensu).to receive(:send_event).with(name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 2)

        ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye", :critical)
      end

      it "error if an invalid level is supplied" do
        expect(ExceptionHandling::Sensu).to_not receive(:send_event)

        expect do
          ExceptionHandling::Sensu.generate_event("world_is_ending", "stick head between knees and kiss ass goodbye", :hair_on_fire)
        end.to raise_exception(RuntimeError, /Invalid alert level/)
      end
    end

    context "#send_event" do
      before do
        @event = { name: "world_is_ending", output: "stick head between knees and kiss ass goodbye", status: 1 }
        @socket = SocketStub.new
      end

      it "send event json to sensu client" do
        expect_any_instance_of(Addrinfo).to receive(:connect).with(any_args) { @socket }
        ExceptionHandling::Sensu.send_event(@event)

        expect(@socket.sent.first).to eq(@event.to_json)
      end
    end
  end
end
