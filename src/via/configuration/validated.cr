module Via::Configuration
  record ListenAddress, host : String, port : Int32

  record Validated,
    listen : ListenAddress,
    routes : Array(Routing::Route),
    tls : TLS? = nil,
    log_file : String? = nil,
    log_level : Logging::Level? = nil
end
