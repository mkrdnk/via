module Via
  class Server
    getter address : Socket::IPAddress?

    def initialize(config : ValidatedConfig, log : IO = STDERR, debug : Bool = false)
      @state = RuntimeState.new(log, debug)
      @state.apply(config)
      @listen = config.listen
      @http_server = HTTP::Server.new { |context| @state.call(context) }
      @address = nil
    end

    def initialize(@listen : ListenAddress, @state : RuntimeState)
      @http_server = HTTP::Server.new { |context| @state.call(context) }
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
      @state.close
    end
  end
end
