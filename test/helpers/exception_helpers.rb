module ExceptionHelpers
  def raise_exception_with_nil_message
    raise exception_with_nil_message
  end

  def exception_with_nil_message
    exception_with_nil_message = RuntimeError.new(nil)
    stub(exception_with_nil_message).message { nil }
    exception_with_nil_message
  end
end
