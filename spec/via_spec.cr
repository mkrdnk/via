require "./spec_helper"

private def with_server(server : HTTP::Server, &)
  address = server.bind_unused_port
  spawn server.listen
  yield address
ensure
  server.close
end

private def with_temp_directory(&)
  path = File.tempname("via-spec", "")
  Dir.mkdir(path)
  yield path
ensure
  FileUtils.rm_rf(path) if path && File.exists?(path)
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

  it "merges a directory of configuration fragments in filename order" do
    with_temp_directory do |directory|
      File.write(File.join(directory, "00-server.yaml"), <<-YAML)
        listen: ":8080"
        YAML
      File.write(File.join(directory, "10-api.yml"), <<-YAML)
        routes:
          - path: /api
            proxy_pass: http://localhost:8000
        YAML
      File.write(File.join(directory, "20-app.yaml"), <<-YAML)
        routes:
          - path: /
            proxy_pass: http://localhost:3000
        YAML

      config = Via::ConfigLoader.new(directory).load.validate
      config.listen.should eq(Via::ListenAddress.new("0.0.0.0", 8080))
      config.routes.map(&.path).should eq(["/api", "/"])
    end
  end

  it "requires one listen declaration across directory fragments" do
    with_temp_directory do |directory|
      File.write(File.join(directory, "one.yaml"), <<-YAML)
        listen: ":8080"
        proxy_pass: http://localhost:3000
        YAML
      File.write(File.join(directory, "two.yaml"), <<-YAML)
        listen: ":8081"
        YAML

      expect_raises(Via::ConfigurationError, "declare listen exactly once") do
        Via::ConfigLoader.new(directory).load
      end
    end
  end

  it "validates manual TLS certificate files" do
    with_temp_directory do |directory|
      cert = File.join(directory, "cert.pem")
      key = File.join(directory, "key.pem")
      File.write(cert, "test certificate")
      File.write(key, "test key")

      config = Via::Config.from_yaml <<-YAML
        listen: ":443"
        tls:
          cert: #{cert}
          key: #{key}
        proxy_pass: http://localhost:3000
        YAML

      validated = config.validate
      validated.tls.not_nil!.cert.should eq(cert)
      validated.tls.not_nil!.key.should eq(key)
    end
  end

  it "rejects missing TLS certificate files" do
    config = Via::Config.from_yaml <<-YAML
      listen: ":443"
      tls:
        cert: /missing/cert.pem
        key: /missing/key.pem
      proxy_pass: http://localhost:3000
      YAML

    expect_raises(Via::ConfigurationError, "tls.cert is not a readable file") do
      config.validate
    end
  end

  {% if flag?(:without_openssl) %}
    it "rejects TLS at runtime in an HTTP-only build" do
      expect_raises(Via::ConfigurationError, "built without OpenSSL") do
        Via::Tls.build(Via::TlsConfig.new("cert.pem", "key.pem"))
      end
    end
  {% end %}
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

describe Via::ErrorPages do
  it "embeds status details and the request ID for every gateway error" do
    statuses = {
      HTTP::Status::BAD_REQUEST,
      HTTP::Status::NOT_FOUND,
      HTTP::Status::BAD_GATEWAY,
      HTTP::Status::SERVICE_UNAVAILABLE,
      HTTP::Status::GATEWAY_TIMEOUT,
    }

    statuses.each do |status|
      body = Via::ErrorPages.body(status, "request-id")
      body.should contain(status.code.to_s)
      body.should contain(status.description.not_nil!)
      body.should contain("Request ID: request-id")
    end
  end
end

describe Via::ConfigWatcher do
  it "debounces a burst of file changes" do
    with_temp_directory do |directory|
      path = File.join(directory, "via.yaml")
      File.write(path, "listen: \":8080\"\n")
      changes = Channel(Nil).new(2)
      watcher = Via::ConfigWatcher.new(path, 10.milliseconds, 30.milliseconds)
      watcher.start { changes.send(nil) }

      begin
        sleep 20.milliseconds
        File.write(path, "listen: \":8081\"\n")
        sleep 15.milliseconds
        File.write(path, "listen: \":8082\"\nproxy_pass: http://localhost\n")

        select
        when changes.receive
        when timeout(1.second)
          fail "configuration watcher did not report a change"
        end

        select
        when changes.receive
          fail "configuration watcher emitted more than one debounced change"
        when timeout(100.milliseconds)
        end
      ensure
        watcher.stop
      end
    end
  end

  it "detects YAML files added to a configuration directory" do
    with_temp_directory do |directory|
      changes = Channel(Nil).new(1)
      watcher = Via::ConfigWatcher.new(directory, 10.milliseconds, 20.milliseconds)
      watcher.start { changes.send(nil) }

      begin
        sleep 20.milliseconds
        File.write(File.join(directory, "route.yaml"), "routes: []\n")

        select
        when changes.receive
        when timeout(1.second)
          fail "configuration watcher did not detect a new YAML file"
        end
      ensure
        watcher.stop
      end
    end
  end

  it "detects changes to additional certificate files" do
    with_temp_directory do |directory|
      config = File.join(directory, "via.yaml")
      cert = File.join(directory, "cert.pem")
      File.write(config, "listen: \":443\"\n")
      File.write(cert, "certificate one")
      changes = Channel(Nil).new(1)
      watcher = Via::ConfigWatcher.new(
        config,
        10.milliseconds,
        20.milliseconds,
        -> { [cert] }
      )
      watcher.start { changes.send(nil) }

      begin
        sleep 20.milliseconds
        File.write(cert, "certificate two")

        select
        when changes.receive
        when timeout(1.second)
          fail "configuration watcher did not detect a certificate change"
        end
      ensure
        watcher.stop
      end
    end
  end
end

describe Via::RuntimeState do
  it "atomically swaps proxy generations" do
    first_entered = Channel(Nil).new(1)
    release_first = Channel(Nil).new(1)
    first_result = Channel(String | Exception).new(1)

    first_upstream = HTTP::Server.new do |context|
      first_entered.send(nil)
      release_first.receive
      context.response << "first"
    end
    second_upstream = HTTP::Server.new do |context|
      context.response << "second"
    end

    with_server(first_upstream) do |first_address|
      with_server(second_upstream) do |second_address|
        state = Via::RuntimeState.new(IO::Memory.new)
        state.apply(Via::ValidatedConfig.new(
          Via::ListenAddress.new("127.0.0.1", 0),
          [Via::Route.new(nil, "/", URI.parse("http://#{first_address}"))]
        ))
        proxy = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
        proxy_address = proxy.bind
        spawn proxy.listen

        begin
          spawn do
            first_result.send(HTTP::Client.get("http://#{proxy_address}/").body)
          rescue ex
            first_result.send(ex)
          end

          first_entered.receive
          state.apply(Via::ValidatedConfig.new(
            Via::ListenAddress.new("127.0.0.1", 0),
            [Via::Route.new(nil, "/", URI.parse("http://#{second_address}"))]
          ))

          HTTP::Client.get("http://#{proxy_address}/").body.should eq("second")
          release_first.send(nil)
          first_result.receive.should eq("first")
        ensure
          select
          when release_first.send(nil)
          else
          end
          proxy.close
        end
      end
    end
  end

  it "reloads a watched configuration file" do
    first_upstream = HTTP::Server.new { |context| context.response << "first-config" }
    second_upstream = HTTP::Server.new { |context| context.response << "second-config" }

    with_server(first_upstream) do |first_address|
      with_server(second_upstream) do |second_address|
        with_temp_directory do |directory|
          path = File.join(directory, "via.yaml")
          File.write(path, <<-YAML)
            listen: "127.0.0.1:8080"
            proxy_pass: http://#{first_address}
            YAML

          initial = Via::ConfigLoader.new(path).load.validate
          state = Via::RuntimeState.new(IO::Memory.new)
          state.apply(initial)
          proxy = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
          proxy_address = proxy.bind
          spawn proxy.listen
          reloader = Via::ConfigReloader.new(
            path,
            initial.listen,
            nil,
            state,
            IO::Memory.new,
            poll_interval: 10.milliseconds,
            debounce: 20.milliseconds
          )
          reloader.start

          begin
            HTTP::Client.get("http://#{proxy_address}/").body.should eq("first-config")
            sleep 20.milliseconds
            File.write(path, <<-YAML)
              listen: "127.0.0.1:8080"
              proxy_pass: http://#{second_address}
              YAML

            deadline = Time.instant + 1.second
            body = ""
            until body == "second-config" || Time.instant >= deadline
              sleep 20.milliseconds
              body = HTTP::Client.get("http://#{proxy_address}/").body
            end
            body.should eq("second-config")

            File.write(path, <<-YAML)
              listen: "127.0.0.1:8080"
              proxy_pass: not-a-url
              YAML
            reloader.reload.should be_false
            HTTP::Client.get("http://#{proxy_address}/").body.should eq("second-config")
          ensure
            reloader.stop
            proxy.close
          end
        end
      end
    end
  end

  it "shows diagnostics in debug mode and recovers after a valid config" do
    upstream = HTTP::Server.new { |context| context.response << "working" }

    with_server(upstream) do |upstream_address|
      log = IO::Memory.new
      state = Via::RuntimeState.new(log, debug: true)
      state.reject("via.yaml", Via::ConfigurationError.new("Invalid upstream URL"))
      proxy = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
      address = proxy.bind
      spawn proxy.listen

      begin
        diagnostic = HTTP::Client.get("http://#{address}/")
        diagnostic.status.should eq(HTTP::Status::SERVICE_UNAVAILABLE)
        diagnostic.body.should contain("via debug")
        diagnostic.body.should contain("via.yaml")
        diagnostic.body.should contain("Invalid upstream URL")

        state.apply(Via::ValidatedConfig.new(
          Via::ListenAddress.new("127.0.0.1", 0),
          [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
        ))
        HTTP::Client.get("http://#{address}/").body.should eq("working")
      ensure
        proxy.close
      end
    end
  end

  it "keeps the previous generation after a production reload error" do
    upstream = HTTP::Server.new { |context| context.response << "unchanged" }

    with_server(upstream) do |upstream_address|
      state = Via::RuntimeState.new(IO::Memory.new)
      state.apply(Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 0),
        [Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))]
      ))
      state.reject("via.yaml", Via::ConfigurationError.new("broken reload"))
      proxy = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
      address = proxy.bind
      spawn proxy.listen

      begin
        HTTP::Client.get("http://#{address}/").body.should eq("unchanged")
      ensure
        proxy.close
      end
    end
  end
end

describe Via::CLI do
  it "documents debug mode in CLI help" do
    output = IO::Memory.new
    Via::CLI.run(["--help"], output, IO::Memory.new).should eq(0)
    output.to_s.should contain("--debug")
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
    received = Channel(Tuple(String, String, String, String, String)).new(1)
    upstream = HTTP::Server.new do |context|
      received.send({
        context.request.headers["Host"],
        context.request.headers["X-Forwarded-Host"],
        context.request.headers["X-Forwarded-Proto"],
        context.request.headers["X-Forwarded-For"],
        context.request.headers["X-Request-ID"],
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
        response = HTTP::Client.get(
          "http://#{proxy_address}/",
          headers: HTTP::Headers{
            "Host"              => "public.example.com:8080",
            "X-Forwarded-For"   => "203.0.113.10",
            "X-Forwarded-Host"  => "spoofed.example.com",
            "X-Forwarded-Proto" => "https",
            "X-Request-ID"      => "client-supplied",
          }
        )
        request_id = response.headers["X-Request-ID"]
        request_id.should match(/\A[0-9a-f]{32}\z/)

        received.receive.should eq({
          upstream_address.to_s,
          "public.example.com:8080",
          "http",
          "203.0.113.10, 127.0.0.1",
          request_id,
        })
      ensure
        proxy.close
      end
    end
  end

  it "marks requests accepted by a TLS listener as HTTPS" do
    forwarded_proto = Channel(String).new(1)
    upstream = HTTP::Server.new do |context|
      forwarded_proto.send(context.request.headers["X-Forwarded-Proto"])
      context.response << "ok"
    end

    with_server(upstream) do |upstream_address|
      route = Via::Route.new(nil, "/", URI.parse("http://#{upstream_address}"))
      handler = Via::Proxy.new([route], IO::Memory.new, false, "https")
      proxy = HTTP::Server.new { |context| handler.call(context) }

      with_server(proxy) do |proxy_address|
        HTTP::Client.get("http://#{proxy_address}/")
        forwarded_proto.receive.should eq("https")
      ensure
        handler.close
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
      request_id = response.headers["X-Request-ID"]
      request_id.should match(/\A[0-9a-f]{32}\z/)
      response.body.should contain("Request ID: #{request_id}")
    ensure
      proxy.close
    end
  end

  it "returns the built-in 400 page when an HTTP/1.1 Host header is missing" do
    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      [Via::Route.new(nil, "/", URI.parse("http://127.0.0.1:1"))]
    )
    proxy = Via::Server.new(config, IO::Memory.new)
    address = proxy.bind
    spawn proxy.listen
    client = TCPSocket.new(address.address, address.port)

    begin
      client << "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"
      client.flush
      wire_response = client.gets_to_end

      wire_response.should contain("HTTP/1.1 400 Bad Request")
      wire_response.should contain("\r\nX-Request-ID: ")
      wire_response.should contain("The request could not be understood.")
      wire_response.should contain("Request ID: ")
    ensure
      client.close
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
    log = IO::Memory.new
    proxy = Via::Server.new(config, log)
    address = proxy.bind
    spawn proxy.listen

    begin
      response = HTTP::Client.get("http://#{address}/")
      response.status.should eq(HTTP::Status::BAD_GATEWAY)
      response.body.should contain("The upstream server could not be reached.")
      request_id = response.headers["X-Request-ID"]
      request_id.should match(/\A[0-9a-f]{32}\z/)
      response.body.should contain("Request ID: #{request_id}")
      log.to_s.should contain("request_id=#{request_id}")
      log.to_s.should contain("error=bad_gateway")
    ensure
      proxy.close
    end
  end
end
