module Via
  class Server
    getter address : Socket::IPAddress?

    def initialize(config : Configuration::Validated, log : IO = STDERR, debug : Bool = false)
      @state = Runtime::State.new(log, debug)
      @state.apply(config)
      @listen = config.listen
      @tls = !config.tls.nil?
      @http_server = ::HTTP::Server.new { |context| @state.call(context) }
      @address = nil
      @mutex = Mutex.new
      @stopped = false
    end

    def initialize(
      @listen : Configuration::ListenAddress,
      @state : Runtime::State,
      @tls : Bool = false,
    )
      @http_server = ::HTTP::Server.new { |context| @state.call(context) }
      @address = nil
      @mutex = Mutex.new
      @stopped = false
    end

    def bind : Socket::IPAddress
      return @address.not_nil! if @address

      if @tls
        {% if flag?(:without_openssl) %}
          raise Configuration::Error.new("TLS is unavailable because Via was built without OpenSSL")
        {% else %}
          tls_server = TLS::ReloadableServer.new(@listen.host, @listen.port, @state)
          @http_server.bind(tls_server)
          @address = tls_server.local_address
        {% end %}
      else
        @address = @http_server.bind_tcp(@listen.host, @listen.port)
      end

      @address.not_nil!
    end

    def listen : Nil
      return if @mutex.synchronize { @stopped }

      bind unless @address
      @http_server.listen
    rescue ex
      raise ex unless @mutex.synchronize { @stopped }
    end

    def stop : Nil
      @mutex.synchronize do
        return if @stopped

        @stopped = true
        @http_server.close
      end
    end

    def begin_shutdown : Nil
      @state.begin_shutdown
    end

    def wait_for_requests : Nil
      @state.wait_for_requests
    end

    def drain_web_sockets : Nil
      @state.drain_web_sockets
    end

    def finish_shutdown : Nil
      @state.close
    end

    def close : Nil
      stop
      finish_shutdown
    end
  end
end
