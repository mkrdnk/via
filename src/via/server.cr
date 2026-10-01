module Via
  class Server
    getter address : Socket::IPAddress?

    def initialize(config : ValidatedConfig, log : IO = STDERR)
      proxy = Proxy.new(config.upstream, log)
      @http_server = HTTP::Server.new { |context| proxy.call(context) }
      @listen = config.listen
      @address = nil
    end

    def bind : Socket::IPAddress
      @address ||= @http_server.bind_tcp(@listen.host, @listen.port)
    end

    def listen : Nil
      bind unless @address
      @http_server.listen
    end

    def close : Nil
      @http_server.close
    end
  end
end
