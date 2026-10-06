require "base64"
{% if flag?(:without_openssl) %}
  require "crystal/digest/sha1"
{% else %}
  require "openssl/sha1"
{% end %}

module Via::Proxy
  # Handles the HTTP/1.1 handshake and raw byte relay for WebSocket upgrades.
  # Upgraded connections are intentionally separate from the reusable HTTP pool.
  module WebSocketTunnel
    extend self

    BUFFER_SIZE = 16 * 1024

    def request?(request : ::HTTP::Request) : Bool
      return false unless request.version == "HTTP/1.1"
      return false unless request.method == "GET"
      return false unless upgrade = request.headers["Upgrade"]?
      return false unless upgrade.compare("websocket", case_insensitive: true) == 0

      request.headers.includes_word?("Connection", "Upgrade")
    end

    def request_headers(
      request : ::HTTP::Request,
      upstream : URI,
      request_id : String,
      scheme : String,
    ) : ::HTTP::Headers
      headers = Via::HTTP::ForwardedHeaders.request(request, upstream, request_id, scheme)
      headers["Connection"] = "Upgrade"
      headers["Upgrade"] = "websocket"
      headers
    end

    def response?(
      request : ::HTTP::Request,
      response : ::HTTP::Client::Response,
    ) : Bool
      return false unless response.status.switching_protocols?
      return false unless upgrade = response.headers["Upgrade"]?
      return false unless upgrade.compare("websocket", case_insensitive: true) == 0
      return false unless response.headers.includes_word?("Connection", "Upgrade")
      return false unless key = request.headers["Sec-WebSocket-Key"]?
      return false unless response.headers["Sec-WebSocket-Accept"]? == key_challenge(key)
      return false if response.headers.has_key?("Content-Length")
      return false if response.headers.has_key?("Transfer-Encoding")

      valid_subprotocol?(request.headers, response.headers)
    end

    def copy_response(
      source : ::HTTP::Headers,
      destination : ::HTTP::Headers,
    ) : Nil
      Via::HTTP::ForwardedHeaders.copy_response(source, destination)
      destination["Connection"] = "Upgrade"
      destination["Upgrade"] = "websocket"
    end

    def connect(
      upstream : URI,
      timeouts : Routing::Timeouts = Routing::Timeouts.new,
    ) : IO
      host = upstream.hostname.not_nil!
      tls = upstream.scheme == "https"
      port = upstream.port || (tls ? 443 : 80)

      {% if flag?(:without_openssl) %}
        if tls
          raise Socket::Error.new(
            "TLS is unavailable because Via was built without OpenSSL"
          )
        end
      {% end %}

      socket = TCPSocket.new(host, port, connect_timeout: timeouts.connect)
      socket.read_timeout = timeouts.read if timeouts.read
      socket.write_timeout = timeouts.write if timeouts.write
      return socket unless tls

      {% if flag?(:without_openssl) %}
        socket
      {% else %}
        begin
          context = OpenSSL::SSL::Context::Client.new
          OpenSSL::SSL::Socket::Client.new(
            socket,
            context: context,
            sync_close: true,
            hostname: host
          )
        rescue ex : OpenSSL::Error
          socket.close
          raise Socket::Error.new("TLS handshake failed: #{ex.message}")
        rescue ex
          socket.close
          raise ex
        end
      {% end %}
    end

    def send_request(
      io : IO,
      request : ::HTTP::Request,
      headers : ::HTTP::Headers,
      resource : String = request.resource,
    ) : Nil
      ::HTTP::Request.new(
        request.method,
        resource,
        headers,
        request.body
      ).to_io(io)
      io.flush
    end

    def read_response(io : IO, & : ::HTTP::Client::Response ->) : Nil
      yielded = false

      begin
        ::HTTP::Client::Response.from_io?(
          io,
          decompress: false
        ) do |response|
          unless response
            raise Socket::Error.new("Upstream closed during WebSocket handshake")
          end

          yielded = true
          yield response
        end
      rescue ex : IO::TimeoutError
        raise ex
      rescue ex
        raise ex if yielded

        raise Socket::Error.new("Invalid upstream response: #{ex.message}")
      end

      raise Socket::Error.new("Invalid upstream response headers") unless yielded
    end

    def upgrade(
      response : ::HTTP::Server::Response,
      upstream : IO,
      logger : Logging::Logger,
      request_id : String,
      upstream_name : String,
      registry : Runtime::WebSocketRegistry,
    ) : Nil
      entry = registry.reserve(upstream)
      begin
        response.upgrade do |downstream|
          next unless registry.attach(entry, downstream)

          begin
            logger.debug(
              "websocket.opened",
              request_id: request_id,
              upstream: upstream_name
            )
            relay(downstream, upstream)
            logger.debug(
              "websocket.closed",
              request_id: request_id,
              upstream: upstream_name
            )
          ensure
            registry.release(entry)
          end
        end
      rescue ex
        registry.release(entry)
        raise ex
      end
    end

    def relay(downstream : IO, upstream : IO) : Nil
      finished = Channel(Nil).new(2)
      spawn copy(downstream, upstream, finished)
      spawn copy(upstream, downstream, finished)

      finished.receive
      close(downstream)
      close(upstream)
      finished.receive
    end

    private def copy(source : IO, destination : IO, finished : Channel(Nil)) : Nil
      buffer = Bytes.new(BUFFER_SIZE)
      while (count = source.read(buffer)) > 0
        destination.write(buffer[0, count])
        destination.flush
      end
    rescue
      # Any transport failure terminates both sides of the tunnel.
    ensure
      finished.send(nil)
    end

    private def close(io : IO) : Nil
      io.close unless io.closed?
    rescue
      # Both relay fibers can observe the same disconnect.
    end

    private def key_challenge(key : String) : String
      value = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
      {% if flag?(:without_openssl) %}
        ::Crystal::Digest::SHA1.base64digest(value)
      {% else %}
        Base64.strict_encode(OpenSSL::SHA1.hash(value))
      {% end %}
    end

    private def valid_subprotocol?(
      request : ::HTTP::Headers,
      response : ::HTTP::Headers,
    ) : Bool
      return true unless selected = response["Sec-WebSocket-Protocol"]?
      return false unless offered = request["Sec-WebSocket-Protocol"]?

      offered.split(',').any? do |protocol|
        protocol.strip == selected
      end
    end
  end
end
