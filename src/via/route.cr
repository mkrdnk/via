module Via
  record StaticTarget, root : String, fallback : String?

  record Route,
    host : String?,
    path : String,
    upstream : URI?,
    static_target : StaticTarget? = nil
end
