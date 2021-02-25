# frozen_string_literal: true

require 'exception_handling/escalate_callback'
require File.expand_path('../../spec_helper',  __dir__)

module ExceptionHandling
  describe EscalateCallback do
    before do
      class TestGem
        class << self
          attr_accessor :logger
        end
        include Escalate.mixin
      end
      TestGem.logger = logger
      Escalate.clear_on_escalate_callbacks
    end

    after do
      Escalate.clear_on_escalate_callbacks
    end

    let(:exception) do
      raise "boom!"
    rescue => ex
      ex
    end
    let(:location_message) { "happened in TestGem" }
    let(:context_hash) { { cuid: 'AABBCD' } }
    let(:logger) { double("logger") }

    it 'registers a callback' do
      EscalateCallback.register!

      expect(logger).to_not receive(:error)
      expect(logger).to_not receive(:fatal)
      expect(ExceptionHandling).to receive(:log_error).with(exception, location_message, context_hash)

      TestGem.escalate(exception, location_message, context_hash)
    end
  end
end
