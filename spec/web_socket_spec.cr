require "http/web_socket"
require "./spec_helper"

private class ExplodingWebSocketIO < IO
  getter? closed = false

  def read(slice : Bytes) : Int32
    raise IO::Error.new("injected relay failure")
  end

  def write(slice : Bytes) : Nil
  end

  def close : Nil
    @closed = true
  end
end

private class BlockingWebSocketIO < IO
  getter? closed = false

  def initialize
    @release = Channel(Nil).new(1)
  end

  def read(slice : Bytes) : Int32
    @release.receive
    0
  end

  def write(slice : Bytes) : Nil
  end

  def close : Nil
    return if closed?

    @closed = true
    select
    when @release.send(nil)
    else
    end
  end
end

private def with_raw_upstream(response : String, &)
  server = TCPServer.new("127.0.0.1", 0)
  address = server.local_address
  spawn do
    client = server.accept
    begin
      while line = client.gets(chomp: true)
        break if line.empty?
      end
      client << response
      client.flush
    rescue IO::Error
      # The proxy can reject the response and close first.
    ensure
      client.close
    end
  end

  yield address
ensure
  server.try(&.close)
end

describe "WebSocket proxying" do
  it "relays text and binary frames with routing and forwarding metadata" do
    handshake = Channel(Tuple(String, String, String, String, String, String, String)).new(1)
    upstream_closed = Channel(Nil).new(1)
    web_socket_handler = HTTP::WebSocketHandler.new(["via.test"]) do |socket, context|
      handshake.send({
        context.request.resource,
        context.request.headers["Host"],
        context.request.headers["X-Forwarded-Host"],
        context.request.headers["X-Forwarded-Proto"],
        context.request.headers["Origin"],
        context.request.headers["Sec-WebSocket-Protocol"],
        context.request.headers["X-Service"],
      })
      socket.on_message { |message| socket.send("echo:#{message}") }
      socket.on_binary { |message| socket.send(message) }
      socket.on_close { upstream_closed.send(nil) }
      socket.send("welcome")
    end
    upstream = HTTP::Server.new([web_socket_handler])

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [
          Via::Route.new(
            "public.example.com",
            "/socket",
            URI.parse("http://#{upstream_address}"),
            strip_prefix: true,
            headers: Via::Routing::HeaderConfig.new(
              request: Via::Routing::HeaderRules.new(
                set: {"X-Service" => "realtime"}
              ),
              response: Via::Routing::HeaderRules.new(
                set: {"X-Frame-Options" => "DENY"}
              )
            )
          ),
        ]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        downstream = TCPSocket.new(proxy_address.address, proxy_address.port)
        key = "MDEyMzQ1Njc4OWFiY2RlZg=="
        downstream << "GET /socket/chat?room=crystal HTTP/1.1\r\n"
        downstream << "Host: public.example.com\r\n"
        downstream << "Connection: Upgrade\r\n"
        downstream << "Upgrade: websocket\r\n"
        downstream << "Origin: https://public.example.com\r\n"
        downstream << "Sec-WebSocket-Version: 13\r\n"
        downstream << "Sec-WebSocket-Key: #{key}\r\n"
        downstream << "Sec-WebSocket-Protocol: via.test\r\n\r\n"
        downstream.flush

        response = HTTP::Client::Response.from_io(downstream, ignore_body: true)
        response.status.should eq(HTTP::Status::SWITCHING_PROTOCOLS)
        response.headers["Sec-WebSocket-Accept"].should eq(
          HTTP::WebSocket::Protocol.key_challenge(key)
        )
        response.headers["Sec-WebSocket-Protocol"].should eq("via.test")
        response.headers["X-Frame-Options"].should eq("DENY")
        protocol = HTTP::WebSocket::Protocol.new(downstream, masked: true)
        socket = HTTP::WebSocket.new(protocol)

        handshake.receive.should eq({
          "/chat?room=crystal",
          upstream_address.to_s,
          "public.example.com",
          "http",
          "https://public.example.com",
          "via.test",
          "realtime",
        })

        socket.receive.should eq("welcome")
        socket.send("hello")
        socket.receive.should eq("echo:hello")

        binary = Bytes[0_u8, 1_u8, 127_u8, 255_u8]
        socket.send(binary)
        socket.receive.should eq(binary)

        socket.close
        select
        when upstream_closed.receive
        when timeout(2.seconds)
          fail "upstream WebSocket remained open after the client disconnected"
        end
      ensure
        socket.try(&.close)
        downstream.try { |io| io.close unless io.closed? }
        proxy.close
      end
    end
  end

  it "passes through an upstream HTTP rejection without upgrading" do
    received_headers = Channel(Tuple(String, String, String?)).new(1)
    upstream = HTTP::Server.new do |context|
      received_headers.send({
        context.request.headers["Connection"],
        context.request.headers["Upgrade"],
        context.request.headers["X-Remove-Me"]?,
      })
      context.response.status = :unauthorized
      context.response.headers["WWW-Authenticate"] = "Bearer"
      context.response << "missing token"
    end

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        response = HTTP::Client.get(
          "http://#{proxy_address}/socket",
          headers: HTTP::Headers{
            "Connection"            => "Upgrade, X-Remove-Me",
            "Upgrade"               => "websocket",
            "Sec-WebSocket-Version" => "13",
            "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
            "X-Remove-Me"           => "private",
          }
        )

        response.status.should eq(HTTP::Status::UNAUTHORIZED)
        response.headers["WWW-Authenticate"].should eq("Bearer")
        response.body.should eq("missing token")
        received_headers.receive.should eq({"Upgrade", "websocket", nil})
      ensure
        proxy.close
      end
    end
  end

  it "returns a gateway timeout when the upstream handshake stalls" do
    upstream = TCPServer.new("127.0.0.1", 0)
    upstream_address = upstream.local_address
    spawn do
      client = upstream.accept
      begin
        while line = client.gets(chomp: true)
          break if line.empty?
        end
        sleep 150.milliseconds
      ensure
        client.close
      end
    end

    route = Via::Route.new(
      nil,
      "/",
      URI.parse("http://#{upstream_address}"),
      timeouts: Via::RoutingTimeouts.new(read: 50.milliseconds)
    )
    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [route]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    proxy_address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get(
        "http://#{proxy_address}/socket",
        headers: HTTP::Headers{
          "Connection"            => "Upgrade",
          "Upgrade"               => "websocket",
          "Sec-WebSocket-Version" => "13",
          "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
        }
      )

      response.status.should eq(HTTP::Status::GATEWAY_TIMEOUT)
      response.body.should contain("<h1>504</h1>")
    ensure
      proxy.close
      upstream.close
    end
  end

  it "returns a bad gateway response for an invalid upstream handshake" do
    upstream = HTTP::Server.new do |context|
      context.response.status = :switching_protocols
      context.response.headers["Connection"] = "Upgrade"
      context.response.headers["Upgrade"] = "websocket"
      context.response.headers["Sec-WebSocket-Accept"] = "invalid"
    end

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        response = HTTP::Client.get(
          "http://#{proxy_address}/socket",
          headers: HTTP::Headers{
            "Connection"            => "Upgrade",
            "Upgrade"               => "websocket",
            "Sec-WebSocket-Version" => "13",
            "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
          }
        )

        response.status.should eq(HTTP::Status::BAD_GATEWAY)
        response.body.should contain("<h1>502</h1>")
      ensure
        proxy.close
      end
    end
  end

  it "returns a bad gateway response for malformed upstream HTTP" do
    responses = [
      "garbage\r\n\r\n",
      "HTTP/1.1 101 Switching Protocols\r\nX-Invalid: \u0001\r\n\r\n",
      "HTTP/1.1 101 Switching Protocols\r\nX-Large: #{"a" * HTTP::MAX_HEADERS_SIZE}\r\n\r\n",
    ]

    responses.each do |raw_response|
      with_raw_upstream(raw_response) do |upstream_address|
        config = Via::ValidatedConfig.new(
          Via::ListenAddress.new("127.0.0.1", 0),
          [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
        )
        proxy = Via::Server.new(config, IO::Memory.new)
        proxy_address = proxy.bind
        spawn proxy.listen

        begin
          response = HTTP::Client.get(
            "http://#{proxy_address}/socket",
            headers: HTTP::Headers{
              "Connection"            => "Upgrade",
              "Upgrade"               => "websocket",
              "Sec-WebSocket-Version" => "13",
              "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
            }
          )

          response.status.should eq(HTTP::Status::BAD_GATEWAY)
        ensure
          proxy.close
        end
      end
    end
  end

  it "rejects framing headers on a switching protocols response" do
    key = "MDEyMzQ1Njc4OWFiY2RlZg=="
    accept = HTTP::WebSocket::Protocol.key_challenge(key)
    framing_headers = [
      "Content-Length: 0",
      "Transfer-Encoding: identity",
    ]

    framing_headers.each do |framing_header|
      raw_response = String.build do |io|
        io << "HTTP/1.1 101 Switching Protocols\r\n"
        io << "Connection: Upgrade\r\n"
        io << "Upgrade: websocket\r\n"
        io << "Sec-WebSocket-Accept: " << accept << "\r\n"
        io << framing_header << "\r\n\r\n"
      end

      with_raw_upstream(raw_response) do |upstream_address|
        config = Via::ValidatedConfig.new(
          Via::ListenAddress.new("127.0.0.1", 0),
          [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
        )
        proxy = Via::Server.new(config, IO::Memory.new)
        proxy_address = proxy.bind
        spawn proxy.listen

        begin
          response = HTTP::Client.get(
            "http://#{proxy_address}/socket",
            headers: HTTP::Headers{
              "Connection"            => "Upgrade",
              "Upgrade"               => "websocket",
              "Sec-WebSocket-Version" => "13",
              "Sec-WebSocket-Key"     => key,
            }
          )

          response.status.should eq(HTTP::Status::BAD_GATEWAY)
        ensure
          proxy.close
        end
      end
    end
  end

  it "cancels the other relay direction after an IO failure" do
    2.times do |index|
      exploding = ExplodingWebSocketIO.new
      blocking = BlockingWebSocketIO.new
      downstream, upstream = index == 0 ? {exploding, blocking} : {blocking, exploding}
      completed = Channel(Exception?).new(1)

      spawn do
        Via::Proxy::WebSocketTunnel.relay(downstream, upstream)
        completed.send(nil)
      rescue ex
        completed.send(ex)
      end

      select
      when error = completed.receive
        error.should be_nil
      when timeout(2.seconds)
        fail "WebSocket relay remained blocked after a transport failure"
      end

      exploding.closed?.should be_true
      blocking.closed?.should be_true
    end
  end

  it "returns a bad gateway response when a secure upstream handshake fails" do
    upstream = TCPServer.new("127.0.0.1", 0)
    upstream_address = upstream.local_address
    {% unless flag?(:without_openssl) %}
      spawn do
        client = upstream.accept
        client.close
      rescue IO::Error
        # The listening socket can close before accept during cleanup.
      end
    {% end %}

    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [Via::Route.new(nil, "/", URI.parse("https://#{upstream_address}"))]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    proxy_address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get(
        "http://#{proxy_address}/socket",
        headers: HTTP::Headers{
          "Connection"            => "Upgrade",
          "Upgrade"               => "websocket",
          "Sec-WebSocket-Version" => "13",
          "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
        }
      )

      response.status.should eq(HTTP::Status::BAD_GATEWAY)
    ensure
      proxy.close
      upstream.close
    end
  end

  {% unless flag?(:without_openssl) %}
    it "closes the secure upstream socket when its handshake times out" do
      upstream_closed = Channel(Exception?).new(1)
      upstream = TCPServer.new("127.0.0.1", 0)
      upstream_address = upstream.local_address
      spawn do
        client = upstream.accept
        begin
          buffer = Bytes.new(4096)
          while client.read(buffer) > 0
          end
          upstream_closed.send(nil)
        rescue ex
          upstream_closed.send(ex)
        ensure
          client.close
        end
      end

      route = Via::Route.new(
        nil,
        "/",
        URI.parse("https://#{upstream_address}"),
        timeouts: Via::RoutingTimeouts.new(read: 50.milliseconds)
      )
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [route]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        response = HTTP::Client.get(
          "http://#{proxy_address}/socket",
          headers: HTTP::Headers{
            "Connection"            => "Upgrade",
            "Upgrade"               => "websocket",
            "Sec-WebSocket-Version" => "13",
            "Sec-WebSocket-Key"     => "MDEyMzQ1Njc4OWFiY2RlZg==",
          }
        )
        response.status.should eq(HTTP::Status::GATEWAY_TIMEOUT)

        select
        when error = upstream_closed.receive
          error.should be_nil
        when timeout(1.second)
          fail "timed-out TLS handshake left the upstream socket open"
        end
      ensure
        proxy.close
        upstream.close
      end
    end
  {% end %}

  it "keeps an upgraded connection open across a configuration reload" do
    web_socket_handler = HTTP::WebSocketHandler.new do |socket, _context|
      socket.on_message { |message| socket.send("old:#{message}") }
    end
    old_upstream = HTTP::Server.new([web_socket_handler])
    new_upstream = HTTP::Server.new { |context| context.response << "new" }

    with_server(old_upstream) do |old_address|
      with_server(new_upstream) do |new_address|
        state = Via::RuntimeState.new(IO::Memory.new)
        state.apply(
          Via::ValidatedConfig.new(
            Via::ListenAddress.new("127.0.0.1", 0),
            [Via::Route.new(nil, "/", URI.parse("http://#{old_address}"))]
          )
        )
        proxy = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
        proxy_address = proxy.bind
        spawn proxy.listen

        begin
          socket = HTTP::WebSocket.new("127.0.0.1", "/", proxy_address.port)
          socket.send("before")
          socket.receive.should eq("old:before")

          state.apply(
            Via::ValidatedConfig.new(
              Via::ListenAddress.new("127.0.0.1", 0),
              [Via::Route.new(nil, "/", URI.parse("http://#{new_address}"))]
            ),
            reloaded: true
          )

          socket.send("after")
          socket.receive.should eq("old:after")
          HTTP::Client.get("http://#{proxy_address}/").body.should eq("new")
        ensure
          socket.try(&.close)
          proxy.close
        end
      end
    end
  end

  it "gives WebSockets their configured grace period during shutdown" do
    web_socket_handler = HTTP::WebSocketHandler.new do |socket, _context|
      socket.on_message { |message| socket.send("echo:#{message}") }
    end
    upstream = HTTP::Server.new([web_socket_handler])

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))],
        websocket_shutdown_timeout: 1.second
      )
      group = Via::ServerGroup.new([Via::Server.new(config, IO::Memory.new)])
      proxy_address = group.bind.first
      spawn group.listen
      socket = HTTP::WebSocket.new("127.0.0.1", "/", proxy_address.port)
      shutdown_done = Channel(Nil).new(1)

      begin
        group.stop
        spawn do
          group.shutdown
          shutdown_done.send(nil)
        end

        socket.send("during-drain")
        socket.receive.should eq("echo:during-drain")
        select
        when shutdown_done.receive
          fail "shutdown did not preserve the WebSocket grace period"
        else
        end

        socket.close
        select
        when shutdown_done.receive
        when timeout(1.second)
          fail "shutdown did not finish after the WebSocket closed"
        end
      ensure
        begin
          socket.close unless socket.closed?
        rescue IO::Error
          # The proxy can close the transport when its grace period expires.
        end
        group.close
      end
    end
  end

  it "closes WebSockets when the shutdown grace period expires" do
    web_socket_handler = HTTP::WebSocketHandler.new do |_socket, _context|
    end
    upstream = HTTP::Server.new([web_socket_handler])

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))],
        websocket_shutdown_timeout: 50.milliseconds
      )
      group = Via::ServerGroup.new([Via::Server.new(config, IO::Memory.new)])
      proxy_address = group.bind.first
      spawn group.listen
      socket = HTTP::WebSocket.new("127.0.0.1", "/", proxy_address.port)

      begin
        started_at = Time.instant
        group.shutdown
        elapsed = Time.instant - started_at

        elapsed.should be >= 40.milliseconds
        elapsed.should be < 1.second
        socket.receive?.should be_nil
      ensure
        begin
          socket.close unless socket.closed?
        rescue IO::Error
          # The proxy closes this transport when the grace period expires.
        end
        group.close
      end
    end
  end
end
