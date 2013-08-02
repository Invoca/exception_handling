_ = ActiveSupport::Testing::SetupAndTeardown::ForClassicTestUnit
module ActiveSupport::Testing::SetupAndTeardown::ForClassicTestUnit
  # This redefinition is unfortunate but test/unit shows us no alternative.
  # Doubly unfortunate: hax to support Mocha's hax.
  # Triply unfortunate to be monkey patching it here. -Colin
  def run(result)
    return if @method_name.to_s == "default_test"

    mocha_counter = retrieve_mocha_counter(self, result)
    yield(Test::Unit::TestCase::STARTED, name)
    @_result = result

    begin
      begin
        run_callbacks :setup do
          setup
          __send__(@method_name)
          mocha_verify(mocha_counter) if mocha_counter
        end
      rescue Mocha::ExpectationError => e
        add_failure(e.message, e.backtrace)
      rescue Test::Unit::AssertionFailedError => e
        add_failure(e.message, e.backtrace)
      rescue Exception => e
        raise if PASSTHROUGH_EXCEPTIONS.include?(e.class)
        add_error(e)
      ensure
        begin
          teardown
          run_callbacks :teardown
        rescue Mocha::ExpectationError => e
          add_failure(e.message, e.backtrace)
        rescue Test::Unit::AssertionFailedError => e
          add_failure(e.message, e.backtrace)
        rescue Exception => e
          raise if PASSTHROUGH_EXCEPTIONS.include?(e.class)
          add_error(e)
        end
      end
    ensure
      mocha_teardown if mocha_counter
    end

    result.add_run
    yield(Test::Unit::TestCase::FINISHED, name)
  end

  protected

  def retrieve_mocha_counter(test_case, result) #:nodoc:
    if respond_to?(:mocha_verify) # using mocha
      if defined?(Mocha::TestCaseAdapter::AssertionCounter)
        Mocha::TestCaseAdapter::AssertionCounter.new(result)
      elsif defined?(Mocha::Integration::TestUnit::AssertionCounter)
        Mocha::Integration::TestUnit::AssertionCounter.new(result)
      elsif defined?(Mocha::MonkeyPatching::TestUnit::AssertionCounter)
        Mocha::MonkeyPatching::TestUnit::AssertionCounter.new(result)
      else
        Mocha::Integration::AssertionCounter.new(test_case)
      end
    end
  end
end
