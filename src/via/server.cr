module Via
  class Server
    getter address : Socket::IPAddress?

    def initialize(config : ValidatedConfig, log : IO = STDERR, debug : Bool = false)
      @state = RuntimeState.new(log, debug)
      @state.apply(config)
      @listen = config.listen
      @tls = !config.tls.nil?
      @http_server = HTTP::Server.new { |context| @state.call(context) }
      @address = nil
    end

    def initialize(@listen : ListenAddress, @state : RuntimeState, @tls : Bool = false)
      @http_server = HTTP::Server.new { |context| @state.call(context) }
      @address = nil
    end

    def bind : Socket::IPAddress
      return @address.not_nil! if @address

      if @tls
        {% if flag?(:without_openssl) %}
          raise ConfigurationError.new("TLS is unavailable because Via was built without OpenSSL")
        {% else %}
          tls_server = ReloadableTlsServer.new(@listen.host, @listen.port, @state)
          @http_server.bind(tls_server)
          @address = tls_server.local_address
        {% end %}
      else
        @address = @http_server.bind_tcp(@listen.host, @listen.port)
      end

      @address.not_nil!
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
