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

    describe '.register_if_configured!' do
      context 'when already configured' do
        before do
          @original_logger = ExceptionHandling.logger
          ExceptionHandling.logger = ::Logger.new('/dev/null')
        end

        after do
          ExceptionHandling.logger = @original_logger
        end

        it 'registers a callback' do
          EscalateCallback.register_if_configured!

          expect(logger).to_not receive(:error)
          expect(logger).to_not receive(:fatal)
          expect(ExceptionHandling).to receive(:log_error).with(exception, location_message, escalate_context: context_hash)

          TestGem.escalate(exception, location_message, context: context_hash)
        end
      end

      context 'when not yet configured' do
        before do
          @original_logger = ExceptionHandling.logger
          ExceptionHandling.logger = nil
        end

        after do
          ExceptionHandling.logger = @original_logger
        end

        it 'registers a callback once the logger is set' do
          EscalateCallback.register_if_configured!

          expect(Escalate.on_escalate_callbacks).to be_empty

          ExceptionHandling.logger = ::Logger.new('/dev/null')
          expect(Escalate.on_escalate_callbacks).to_not be_empty

          expect(logger).to_not receive(:error)
          expect(logger).to_not receive(:fatal)
          expect(ExceptionHandling).to receive(:log_error).with(exception, location_message, escalate_context: context_hash)

          TestGem.escalate(exception, location_message, context: context_hash)
        end
      end
    end
  end
end
