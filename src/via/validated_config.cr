module Via
  record ListenAddress, host : String, port : Int32

  record ValidatedConfig,
    listen : ListenAddress,
    routes : Array(Route),
    tls : TlsConfig? = nil
end
