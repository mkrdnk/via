module Via::Configuration
  DEFAULT_WEBSOCKET_SHUTDOWN_TIMEOUT = 5.seconds

  record ListenAddress, host : String, port : Int32

  record Validated,
    listen : ListenAddress,
    routes : Array(Routing::Route),
    tls : TLS? = nil,
    log_file : String? = nil,
    log_level : Logging::Level? = nil,
    config_file : String? = nil,
    debug : Bool = false,
    websocket_shutdown_timeout : Time::Span = DEFAULT_WEBSOCKET_SHUTDOWN_TIMEOUT
end
