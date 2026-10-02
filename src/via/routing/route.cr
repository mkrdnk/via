module Via::Routing
  record StaticTarget, root : String, fallback : String?

  record Route,
    host : String?,
    path : String,
    upstream : URI?,
    static_target : StaticTarget? = nil,
    response_status : Int32? = nil
end
