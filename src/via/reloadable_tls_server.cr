module Via
  {% unless flag?(:without_openssl) %}
    class ReloadableTlsServer
      include Socket::Server

      getter local_address : Socket::IPAddress

      def initialize(host : String, port : Int32, @state : RuntimeState)
        @tcp_server = TCPServer.new(host, port)
        @local_address = @tcp_server.local_address
      end

      def accept : OpenSSL::SSL::Socket::Server
        wrap(@tcp_server.accept)
      end

      def accept? : OpenSSL::SSL::Socket::Server?
        if socket = @tcp_server.accept?
          wrap(socket)
        end
      end

      def close : Nil
        @tcp_server.close
      end

      private def wrap(socket : IO) : OpenSSL::SSL::Socket::Server
        OpenSSL::SSL::Socket::Server.new(
          socket,
          @state.tls_context,
          sync_close: true,
          accept: false
        )
      end
    end
  {% end %}
end
