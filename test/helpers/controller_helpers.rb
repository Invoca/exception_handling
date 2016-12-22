module ControllerHelpers
  DummyController = Struct.new(:complete_request_uri, :request, :session)
  DummyRequest = Struct.new(:env, :parameters, :session_options)

  def create_dummy_controller(env, parameters, session, request_uri)
    request = DummyRequest.new(env, parameters, session)
    DummyController.new(request_uri, request, session)
  end
end
