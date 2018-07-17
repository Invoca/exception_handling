module ControllerHelpers
  DummyController = Struct.new(:complete_request_uri, :request, :session)
  DummyRequest = Struct.new(:env, :parameters, :session_options)
  
  class DummySession
    def initialize(data)
      @data = data
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end

    def to_hash
      @data
    end
  end

  def create_dummy_controller(env, parameters, session, request_uri)
    request = DummyRequest.new(env, parameters, DummySession.new(session))
    DummyController.new(request_uri, request, DummySession.new(session))
  end
end
