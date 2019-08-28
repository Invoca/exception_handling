# frozen_string_literal: true

module ExceptionHelpers
  def raise_exception_with_nil_message
    raise exception_with_nil_message
  end

  def exception_with_nil_message
    exception_with_nil_message = RuntimeError.new(nil)
    stub(exception_with_nil_message).message { nil }
    exception_with_nil_message
  end

  attr_reader :sent_notifications

  def capture_notifications
    @sent_notifications = []
    stub(ExceptionHandling).send_exception_to_honeybadger(anything) { |exception_info| @sent_notifications << exception_info }
  end
end
