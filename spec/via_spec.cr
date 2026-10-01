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
    received = Channel(Tuple(String, String, String, String)).new(1)
    upstream = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      received.send({
        context.request.method,
        context.request.resource,
        context.request.headers["X-Test"],
        body,
      })
      context.response.status = :created
      context.response.headers["X-Upstream"] = "yes"
      context.response << "upstream:#{body}"
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
        response.body.should eq("upstream:request-body")
        received.receive.should eq({
          "POST",
          "/upload?part=2",
          "forwarded",
          "request-body",
        })
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
