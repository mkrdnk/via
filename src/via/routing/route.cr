module Via::Routing
  record StaticTarget, root : String, fallback : String?

  record ReturnTarget, status : Int32, location : String?

  record Timeouts,
    connect : Time::Span? = nil,
    read : Time::Span? = nil,
    write : Time::Span? = nil

  record HeaderRules,
    set : Hash(String, String) = Hash(String, String).new,
    remove : Array(String) = Array(String).new

  record HeaderConfig,
    request : HeaderRules = HeaderRules.new,
    response : HeaderRules = HeaderRules.new

  record Route,
    host : String?,
    path : String,
    upstream : URI?,
    static_target : StaticTarget? = nil,
    response_status : Int32? = nil,
    timeouts : Timeouts = Timeouts.new,
    return_target : ReturnTarget? = nil,
    strip_prefix : Bool = false,
    headers : HeaderConfig = HeaderConfig.new
end
