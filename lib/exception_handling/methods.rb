module ExceptionHandling
  module Methods # included on models and controllers

    protected

    def log_error(exception_or_string, exception_context = '')
      controller = self if respond_to?(:request) && respond_to?(:session)
      ExceptionHandling.log_error(exception_or_string, exception_context, controller)
    end

    def log_error_rack(exception_or_string, exception_context = '', rack_filter = '')
      ExceptionHandling.log_error_rack(exception_or_string, exception_context, rack_filter)
    end

    def log_warning(message)
      log_error(Warning.new(message))
    end

    def log_info(message)
      ExceptionHandling.logger.info( message )
    end

    def log_debug(message)
      ExceptionHandling.logger.debug( message )
    end

    def ensure_safe(exception_context = "")
      begin
        yield
      rescue => ex
        log_error ex, exception_context
        nil
      end
    end

    def escalate_error(exception_or_string, email_subject)
      ExceptionHandling.escalate_error(exception_or_string, email_subject)
    end

    def escalate_warning(message, email_subject)
      ExceptionHandling.escalate_warning(message, email_subject)
    end

    def ensure_escalation(*args)
      ExceptionHandling.ensure_escalation(*args) do
        yield
      end
    end

    # Store aside the current controller when included
    LONG_REQUEST_SECONDS = (defined?(Rails) && Rails.env == 'test' ? 300 : 30)
    def set_current_controller
      ExceptionHandling.current_controller = self
      result = nil
      time = Benchmark.measure do
        result = yield
      end
      name = " in #{controller_name}::#{action_name}" rescue " "
      log_error( "Long controller action detected#{name} %.4fs  " % time.real ) if time.real > LONG_REQUEST_SECONDS && !['development', 'test'].include?(ExceptionHandling.email_environment)
      result
    ensure
      ExceptionHandling.current_controller = nil
    end

    def self.included( controller )
      controller.around_filter :set_current_controller if controller.respond_to? :around_filter
    end
  end
end