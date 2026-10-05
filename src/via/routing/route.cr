module Via::Routing
  record StaticTarget, root : String, fallback : String?

  record ReturnTarget, status : Int32, location : String?

  record Timeouts,
    connect : Time::Span? = nil,
    read : Time::Span? = nil,
    write : Time::Span? = nil

  record Route,
    host : String?,
    path : String,
    upstream : URI?,
    static_target : StaticTarget? = nil,
    response_status : Int32? = nil,
    timeouts : Timeouts = Timeouts.new,
    return_target : ReturnTarget? = nil
end
