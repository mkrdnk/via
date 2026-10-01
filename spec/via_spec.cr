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
    validated.upstream.host.should eq("localhost")
    validated.upstream.port.should eq(3000)
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
        URI.parse("http://#{upstream_address}")
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
        URI.parse("http://#{upstream_address}")
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

  it "returns 502 when the upstream cannot be reached" do
    unavailable = TCPServer.new("127.0.0.1", 0)
    port = unavailable.local_address.port
    unavailable.close

    config = Via::ValidatedConfig.new(
      Via::ListenAddress.new("127.0.0.1", 0),
      URI.parse("http://127.0.0.1:#{port}")
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
