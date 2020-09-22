# frozen_string_literal: true

require File.expand_path('../../test_helper',  __dir__)

require "exception_handling/testing"
require_relative '../../helpers/exception_helpers.rb'

module ExceptionHandling
  describe Methods do
    include ExceptionHelpers

    def dont_stub_log_error
      true
    end

    context "ExceptionHandling.Methods" do
      before do
        @controller = Testing::ControllerStub.new
        ExceptionHandling.stub_handler = nil
      end

      it "set the around filter" do
        expect(Testing::ControllerStub.around_filter_method).to eq(:set_current_controller)
        expect(ExceptionHandling.current_controller).to be_nil
        @controller.simulate_around_filter do
          expect(ExceptionHandling.current_controller).to eq(@controller)
        end
        expect(ExceptionHandling.current_controller).to be_nil
      end

      it "use the current_controller when available" do
        capture_notifications

        expect(ExceptionHandling.logger).to receive(:fatal).with(/blah/, anything)
        @controller.simulate_around_filter do
          ExceptionHandling.log_error(ArgumentError.new("blah"))
          expect(sent_notifications.size).to eq(1)
          expect(sent_notifications.last.enhanced_data['request'].to_s).to match(@controller.request.request_uri)
        end
      end

      it "report long running controller action" do
        expect(@controller.send(:long_controller_action_timeout)).to eq(2)
        expect(ExceptionHandling).to receive(:log_error).with(/Long controller action detected in #{@controller.class.name.split("::").last}::test_action/, anything, anything)
        @controller.simulate_around_filter do
          sleep(3)
        end
      end

      it "not report long running controller actions if it is less than the timeout" do
        expect(@controller.send(:long_controller_action_timeout)).to eq(2)
        allow(ExceptionHandling).to receive(:log_error).and_return(flunk "Should not timeout")
        @controller.simulate_around_filter do
          sleep(1)
        end
      end

      it "default long running controller action(300/30 for test/prod)" do
        class DummyController
          include ExceptionHandling::Methods
        end

        controller = DummyController.new

        Rails.env = 'production'
        expect(controller.send(:long_controller_action_timeout)).to eq(30)

        Rails.env = 'test'
        expect(controller.send(:long_controller_action_timeout)).to eq(300)
      end

      context "#log_warning" do
        it "be available to the controller" do
          expect(@controller.methods.include?(:log_warning)).to eq(true)
        end

        it "call ExceptionHandling#log_warning" do
          expect(ExceptionHandling).to receive(:log_warning).with("Hi mom")
          @controller.send(:log_warning, "Hi mom")
        end
      end
    end

  end
end
