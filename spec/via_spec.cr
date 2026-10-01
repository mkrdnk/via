require "./spec_helper"

private def with_server(server : HTTP::Server, &)
  address = server.bind_unused_port
  spawn server.listen
  yield address
ensure
  server.close
end

describe Via::Config do
  it "loads and validates the minimal configuration" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":8080"
      proxy_pass: http://localhost:3000
      YAML

    validated = config.validate
    validated.listen.should eq(Via::ListenAddress.new("0.0.0.0", 8080))
    validated.routes.should eq([
      Via::Route.new(nil, "/", URI.parse("http://localhost:3000")),
    ])
  end

  it "loads and normalizes route configuration" do
    config = Via::Config.from_yaml <<-YAML
      listen: "127.0.0.1:8080"
      routes:
        - host: API.Example.COM
          path: /api/
          proxy_pass: http://localhost:8000
        - path: /
          proxy_pass: http://localhost:3000
      YAML

    routes = config.validate.routes
    routes[0].host.should eq("api.example.com")
    routes[0].path.should eq("/api")
    routes[1].host.should be_nil
  end

  it "rejects unknown fields" do
    expect_raises(YAML::ParseException) do
      Via::Config.from_yaml <<-YAML
        listen: ":8080"
        proxy_pass: http://localhost:3000
        typo: true
        YAML
    end
  end

  it "rejects upstream URLs with an unsupported scheme" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":8080"
      proxy_pass: ftp://localhost:3000
      YAML

    expect_raises(Via::ConfigurationError, "Invalid upstream URL") do
      config.validate
    end
  end

  it "rejects an empty upstream host" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":8080"
      proxy_pass: http://:3000
      YAML

    expect_raises(Via::ConfigurationError, "Invalid upstream URL") do
      config.validate
    end
  end

  it "rejects mixing top-level proxy_pass with routes" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":8080"
      proxy_pass: http://localhost:3000
      routes:
        - path: /
          proxy_pass: http://localhost:8000
      YAML

    expect_raises(Via::ConfigurationError, "Use either proxy_pass or routes") do
      config.validate
    end
  end

  it "rejects duplicate normalized routes" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":8080"
      routes:
        - host: example.com
          path: /api
          proxy_pass: http://localhost:3000
        - host: EXAMPLE.COM
          path: /api/
          proxy_pass: http://localhost:8000
      YAML

    expect_raises(Via::ConfigurationError, "Duplicate route") do
      config.validate
    end
  end
end

describe Via::Router do
  root = Via::Route.new(nil, "/", URI.parse("http://root"))
  api = Via::Route.new(nil, "/api", URI.parse("http://api"))
  api_v2 = Via::Route.new(nil, "/api/v2", URI.parse("http://api-v2"))
  hosted = Via::Route.new("api.example.com", "/api", URI.parse("http://hosted"))
  router = Via::Router.new([root, api, api_v2, hosted])

  it "uses segment-aware prefix matching and the longest path" do
    router.match(nil, "/api").should eq(api)
    router.match(nil, "/api/users").should eq(api)
    router.match(nil, "/api/v2/users").should eq(api_v2)
    router.match(nil, "/apix").should eq(root)
  end

  it "matches hosts case-insensitively and ignores the request port" do
    router.match("API.Example.COM:8080", "/api/users").should eq(hosted)
  end

  it "prefers a host-specific route when paths have equal length" do
    router.match("api.example.com", "/api").should eq(hosted)
    router.match("other.example.com", "/api").should eq(api)
  end

  it "returns nil when no route matches" do
    host_only = Via::Router.new([
      Via::Route.new("example.com", "/", URI.parse("http://example")),
    ])

    host_only.match("other.example.com", "/").should be_nil
  end
end

describe Via::Proxy do
  it "removes standard and Connection-nominated hop-by-hop headers" do
    source = HTTP::Headers{
      "Connection"   => "keep-alive, X-Internal",
      "Keep-Alive"   => "timeout=5",
      "X-Internal"   => "secret",
      "X-End-To-End" => "kept",
    }

    headers = Via::Proxy.forwarded_headers(source)
    headers["X-End-To-End"].should eq("kept")
    headers.has_key?("Connection").should be_false
    headers.has_key?("Keep-Alive").should be_false
    headers.has_key?("X-Internal").should be_false
  end

  it "forwards method, path, query, headers, status, headers, and bodies" do
    received = Channel(Tuple(String, String, String, String, String)).new(1)
    upstream = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      received.send({
        context.request.method,
        context.request.resource,
        context.request.headers["X-Test"],
        context.request.headers["Content-Length"],
        body,
      })
      response_body = "upstream:#{body}"
      context.response.status = :created
      context.response.headers["X-Upstream"] = "yes"
      context.response.content_length = response_body.bytesize
      context.response << response_body
    end

    with_server(upstream) do |upstream_address|
      proxy_config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(proxy_config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        headers = HTTP::Headers{"X-Test" => "forwarded"}
        response = HTTP::Client.post(
          "http://#{proxy_address}/upload?part=2",
          headers: headers,
          body: "request-body"
        )

        response.status.should eq(HTTP::Status::CREATED)
        response.headers["X-Upstream"].should eq("yes")
        response.headers["Content-Length"].should eq("21")
        response.body.should eq("upstream:request-body")
        received.receive.should eq({
          "POST",
          "/upload?part=2",
          "forwarded",
          "12",
          "request-body",
        })
      ensure
        proxy.close
      end
    end
  end

  it "sets Host and X-Forwarded request metadata" do
    received = Channel(Tuple(String, String, String, String)).new(1)
    upstream = HTTP::Server.new do |context|
      received.send({
        context.request.headers["Host"],
        context.request.headers["X-Forwarded-Host"],
        context.request.headers["X-Forwarded-Proto"],
        context.request.headers["X-Forwarded-For"],
      })
      context.response << "ok"
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
        HTTP::Client.get(
          "http://#{proxy_address}/",
          headers: HTTP::Headers{
            "Host"              => "public.example.com:8080",
            "X-Forwarded-For"   => "203.0.113.10",
            "X-Forwarded-Host"  => "spoofed.example.com",
            "X-Forwarded-Proto" => "https",
          }
        )

        received.receive.should eq({
          upstream_address.to_s,
          "public.example.com:8080",
          "http",
          "203.0.113.10, 127.0.0.1",
        })
      ensure
        proxy.close
      end
    end
  end

  it "reframes chunked bodies without buffering them" do
    received = Channel(Tuple(String?, String?, String)).new(1)
    upstream = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      received.send({
        context.request.headers["Transfer-Encoding"]?,
        context.request.headers["Content-Length"]?,
        body,
      })
      context.response << "chunked-response"
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
        client = HTTP::Client.new(proxy_address.address, proxy_address.port)
        response = client.exec("POST", "/", body: IO::Memory.new("chunked-request"))

        response.body.should eq("chunked-response")
        received.receive.should eq({"chunked", nil, "chunked-request"})
      ensure
        client.try(&.close)
        proxy.close
      end
    end
  end

  it "streams a large request before the upload is complete" do
    chunk_size = 64 * 1024
    body_size = 8 * 1024 * 1024
    first_chunk_received = Channel(Nil).new(1)
    received_size = Channel(Int64).new(1)

    upstream = HTTP::Server.new do |context|
      body = context.request.body.not_nil!
      first_byte = Bytes.new(1)
      body.read_fully(first_byte)
      first_chunk_received.send(nil)

      buffer = Bytes.new(chunk_size)
      total = first_byte.size.to_i64
      while (count = body.read(buffer)) > 0
        total += count
      end
      received_size.send(total)
      context.response << "uploaded"
    end

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen
      client = TCPSocket.new(proxy_address.address, proxy_address.port)

      begin
        client << "POST /upload HTTP/1.1\r\n"
        client << "Host: upload.example.com\r\n"
        client << "Content-Length: #{body_size}\r\n"
        client << "Connection: close\r\n\r\n"

        chunk = Bytes.new(chunk_size, 0x61_u8)
        client.write(chunk)
        client.flush

        select
        when first_chunk_received.receive
        when timeout(2.seconds)
          fail "proxy waited for the complete request body before forwarding it"
        end

        remaining = body_size - chunk_size
        while remaining > 0
          count = Math.min(remaining, chunk.size)
          client.write(chunk[0, count])
          remaining -= count
        end
        client.flush

        received_size.receive.should eq(body_size)
        client.gets_to_end.should contain("uploaded")
      ensure
        client.close
        proxy.close
      end
    end
  end

  it "streams a response before the upstream body is complete" do
    chunk = Bytes.new(64 * 1024, 0x62_u8)
    release_upstream = Channel(Nil).new(1)
    first_chunk_received = Channel(Int32 | Exception).new(1)
    received_size = Channel(Int64 | Exception).new(1)

    upstream = HTTP::Server.new do |context|
      context.response.write(chunk)
      context.response.flush
      release_upstream.receive
      context.response.write(chunk)
    end

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      spawn do
        client = HTTP::Client.new(proxy_address.address, proxy_address.port)
        client.get("/") do |response|
          buffer = Bytes.new(16 * 1024)
          count = response.body_io.read(buffer)
          first_chunk_received.send(count)

          total = count.to_i64
          while (count = response.body_io.read(buffer)) > 0
            total += count
          end
          received_size.send(total)
        end
      rescue ex
        first_chunk_received.send(ex)
        received_size.send(ex)
      ensure
        client.try(&.close)
      end

      begin
        select
        when first = first_chunk_received.receive
          first.should be_a(Int32)
          first.as(Int32).should be > 0
        when timeout(2.seconds)
          fail "proxy waited for the complete upstream body before forwarding it"
        end
      ensure
        release_upstream.send(nil)
      end

      result = received_size.receive
      result.should eq((chunk.size * 2).to_i64)
    ensure
      proxy.try(&.close)
    end
  end

  it "preserves upstream redirects without rewriting Location" do
    upstream = HTTP::Server.new do |context|
      context.response.status = :temporary_redirect
      context.response.headers["Location"] = "/login?next=%2Fprivate"
      context.response << "redirecting"
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
        response = HTTP::Client.get("http://#{proxy_address}/private")
        response.status.should eq(HTTP::Status::TEMPORARY_REDIRECT)
        response.headers["Location"].should eq("/login?next=%2Fprivate")
      ensure
        proxy.close
      end
    end
  end

  it "returns 502 when an upstream disconnects without a response" do
    upstream = TCPServer.new("127.0.0.1", 0)
    upstream_address = upstream.local_address

    spawn do
      socket = upstream.accept
      while line = socket.gets
        break if line.empty?
      end
      socket.close
    end

    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get("http://#{address}/")
      response.status.should eq(HTTP::Status::BAD_GATEWAY)
    ensure
      proxy.close
      upstream.close
    end
  end

  it "keeps serving after a downstream client disconnects" do
    slow_started = Channel(Nil).new(1)
    release_slow_response = Channel(Nil).new(1)
    slow_finished = Channel(Nil).new(1)
    chunk = Bytes.new(64 * 1024, 0x63_u8)

    upstream = HTTP::Server.new do |context|
      if context.request.path == "/slow"
        slow_started.send(nil)
        release_slow_response.receive
        begin
          256.times { context.response.write(chunk) }
        rescue IO::Error
          # The proxy closes this upstream connection after its client leaves.
        ensure
          slow_finished.send(nil)
        end
      else
        context.response << "still-running"
      end
    end

    with_server(upstream) do |upstream_address|
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen
      abandoned_client = TCPSocket.new(proxy_address.address, proxy_address.port)

      begin
        abandoned_client << "GET /slow HTTP/1.1\r\n"
        abandoned_client << "Host: example.com\r\n\r\n"
        abandoned_client.flush
        slow_started.receive
        abandoned_client.close
        release_slow_response.send(nil)

        select
        when slow_finished.receive
        when timeout(2.seconds)
          fail "upstream stream remained blocked after the client disconnected"
        end

        response = HTTP::Client.get("http://#{proxy_address}/health")
        response.body.should eq("still-running")
      ensure
        abandoned_client.close unless abandoned_client.closed?
        proxy.close
      end
    end
  end

  it "reuses an idle upstream connection" do
    remote_ports = Channel(Int32).new(2)
    upstream = HTTP::Server.new do |context|
      address = context.request.remote_address.as(Socket::IPAddress)
      remote_ports.send(address.port)
      context.response << "ok"
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
        2.times { HTTP::Client.get("http://#{proxy_address}/") }
        first_port = remote_ports.receive
        remote_ports.receive.should eq(first_port)
      ensure
        proxy.close
      end
    end
  end

  it "proxies independent connections concurrently" do
    entered = Channel(Nil).new(2)
    release = Channel(Nil).new(2)
    results = Channel(String | Exception).new(2)

    upstream = HTTP::Server.new do |context|
      entered.send(nil)
      release.receive
      context.response << context.request.resource
    end

    with_server(upstream) do |upstream_address|
      proxy_config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      )
      proxy = Via::Server.new(proxy_config, IO::Memory.new)
      proxy_address = proxy.bind
      spawn proxy.listen

      begin
        2.times do |index|
          spawn do
            response = HTTP::Client.get("http://#{proxy_address}/#{index}")
            results.send(response.body)
          rescue ex
            results.send(ex)
          end
        end

        2.times do
          select
          when entered.receive
          when timeout(2.seconds)
            fail "proxy serialized two independent client connections"
          end
        end
      ensure
        2.times { release.send(nil) }
      end

      2.times do
        result = results.receive
        result.should be_a(String)
      end
    ensure
      proxy.try(&.close)
    end
  end

  it "routes by host and path without rewriting the request target" do
    api = HTTP::Server.new do |context|
      context.response << "api:#{context.request.resource}"
    end
    app = HTTP::Server.new do |context|
      context.response << "app:#{context.request.resource}"
    end

    with_server(api) do |api_address|
      with_server(app) do |app_address|
        config = Via::Config.from_yaml <<-YAML
          listen: "127.0.0.1:8080"
          routes:
            - host: api.example.com
              path: /api
              proxy_pass: http://#{api_address}
            - path: /
              proxy_pass: http://#{app_address}
          YAML
        validated = config.validate
        proxy = Via::Server.new(
          Via::ValidatedConfig.new(Via::ListenAddress.new("127.0.0.1", 0), validated.routes),
          IO::Memory.new
        )
        proxy_address = proxy.bind
        spawn proxy.listen

        begin
          api_response = HTTP::Client.get(
            "http://#{proxy_address}/api/users?active=true",
            headers: HTTP::Headers{"Host" => "api.example.com"}
          )
          app_response = HTTP::Client.get(
            "http://#{proxy_address}/api/users?active=true",
            headers: HTTP::Headers{"Host" => "www.example.com"}
          )

          api_response.body.should eq("api:/api/users?active=true")
          app_response.body.should eq("app:/api/users?active=true")
        ensure
          proxy.close
        end
      end
    end
  end

  it "returns 404 when no route matches" do
    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [Via::Route.new("example.com", "/", URI.parse("http://127.0.0.1:1"))]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get(
        "http://#{address}/",
        headers: HTTP::Headers{"Host" => "other.example.com"}
      )
      response.status.should eq(HTTP::Status::NOT_FOUND)
      response.body.should contain("No route matched this request.")
    ensure
      proxy.close
    end
  end

  it "returns 502 when the upstream cannot be reached" do
    unavailable = TCPServer.new("127.0.0.1", 0)
    port = unavailable.local_address.port
    unavailable.close

    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [Via::Route.new(nil, "/", URI.parse("http://127.0.0.1:#{port}"))]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get("http://#{address}/")
      response.status.should eq(HTTP::Status::BAD_GATEWAY)
      response.body.should contain("The upstream server could not be reached.")
    ensure
      proxy.close
    end
  end
end
