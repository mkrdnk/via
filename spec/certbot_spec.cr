require "./spec_helper"

{% unless flag?(:without_openssl) %}
  private def certbot_peer_digest(address : Socket::IPAddress) : String
    tcp = TCPSocket.new(address.address, address.port)
    tcp.read_timeout = 2.seconds
    tcp.write_timeout = 2.seconds
    socket = OpenSSL::SSL::Socket::Client.new(tcp,
      context: OpenSSL::SSL::Context::Client.insecure, sync_close: true)
    socket.peer_certificate.digest("SHA256").hexstring
  ensure
    socket.try(&.close)
    tcp.try(&.close)
  end
{% end %}

describe "Certbot integration" do
  it "serves webroot challenges ahead of the HTTPS redirect without exposing other files" do
    with_temp_directory do |directory|
      challenge_root = File.join(directory, ".well-known", "acme-challenge")
      FileUtils.mkdir_p(challenge_root)
      File.write(File.join(challenge_root, "token"), "token.thumbprint")
      File.write(File.join(directory, "private"), "not public")
      config = Via::Config.from_yaml(<<-YAML).validate
        listen: "127.0.0.1:8080"
        routes:
          - host: example.com
            path: /.well-known/acme-challenge
            static: #{challenge_root}
          - host: example.com
            path: /
            return: 301 https://example.com
        YAML
      state = Via::RuntimeState.new(IO::Memory.new)
      state.apply(config)
      server = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state)
      address = server.bind
      spawn server.listen

      begin
        headers = HTTP::Headers{"Host" => "example.com"}
        challenge = HTTP::Client.get("http://#{address}/.well-known/acme-challenge/token", headers)
        challenge.status.should eq(HTTP::Status::OK)
        challenge.body.should eq("token.thumbprint")
        challenge.headers.has_key?("Location").should be_false
        HTTP::Client.get("http://#{address}/.well-known/acme-challenge/missing", headers)
          .status.should eq(HTTP::Status::NOT_FOUND)
        HTTP::Client.get("http://#{address}/.well-known/acme-challenge/%2e%2e/%2e%2e/private", headers)
          .status.should eq(HTTP::Status::NOT_FOUND)
        HTTP::Client.get("http://#{address}/.well-known/acme-challenge/token",
          HTTP::Headers{"Host" => "other.example"}).status.should eq(HTTP::Status::NOT_FOUND)
        redirect = HTTP::Client.get("http://#{address}/", headers)
        redirect.status.should eq(HTTP::Status::MOVED_PERMANENTLY)
        redirect.headers["Location"].should eq("https://example.com")
      ensure
        server.close
      end
    end
  end

  {% unless flag?(:without_openssl) %}
    if openssl = Process.find_executable("openssl")
      it "loads a combined PEM and automatically reloads an atomic replacement" do
        with_temp_directory do |directory|
          bundle = File.join(directory, "tls.pem")
          config_path = File.join(directory, "via.yaml")
          File.write(config_path, <<-YAML)
            listen: "127.0.0.1:8443"
            tls:
              cert: #{bundle}
              key: #{bundle}
            routes:
              - path: /
                return: 200
            YAML
          bundles = (1..2).map do |serial|
            cert = File.join(directory, "cert#{serial}.pem")
            key = File.join(directory, "key#{serial}.pem")
            output = IO::Memory.new
            status = Process.run(openssl, [
              "req", "-x509", "-newkey", "rsa:2048", "-nodes",
              "-keyout", key, "-out", cert, "-days", "1",
              "-subj", "/CN=localhost", "-set_serial", serial.to_s,
            ], output: output, error: output)
            status.success?.should be_true, output.to_s
            File.read(cert) + File.read(key)
          end
          File.write(bundle, bundles[0])
          models = Via::ConfigLoader.new(directory).load_all
          config = models.first.validate
          state = Via::RuntimeState.new(IO::Memory.new)
          state.apply(config)
          server = Via::Server.new(Via::ListenAddress.new("127.0.0.1", 0), state, tls: true)
          address = server.bind
          spawn server.listen
          reloader = Via::Configuration::GroupReloader.new(
            directory, [config.listen], [true], [state],
            10.milliseconds, 20.milliseconds
          )
          reloader.set_dependencies(models)
          reloader.start
          client_context = OpenSSL::SSL::Context::Client.insecure

          begin
            client = HTTP::Client.new(address.address, address.port, tls: client_context)
            client.get("/").status.should eq(HTTP::Status::OK)
            client.close
            previous_digest = certbot_peer_digest(address)
            previous = state.tls_context
            sleep 30.milliseconds
            staged = File.join(directory, "staged.pem")
            File.write(staged, bundles[1])
            File.rename(staged, bundle)
            deadline = Time.instant + 2.seconds
            while state.tls_context.same?(previous) && Time.instant < deadline
              sleep 10.milliseconds
            end
            state.tls_context.same?(previous).should be_false
            client = HTTP::Client.new(address.address, address.port, tls: client_context)
            client.get("/").status.should eq(HTTP::Status::OK)
            certbot_peer_digest(address).should_not eq(previous_digest)
          ensure
            client.try(&.close)
            reloader.stop
            server.close
          end
        end
      end
    else
      pending "loads and reloads a Certbot PEM bundle (requires the openssl CLI)"
    end
  {% end %}
end
