require "./spec_helper"

describe Via::Console::Banner do
  it "renders a compact single-upstream startup summary" do
    config = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 8080),
      [
        Via::Routing::Route.new(
          nil,
          "/",
          URI.parse("http://localhost:3000")
        ),
      ]
    )
    output = IO::Memory.new

    Via::Console::Banner.render(
      output,
      config_path: "/etc/via/config.yaml",
      listen: ":8080",
      config: config,
      debug: false
    )

    text = output.to_s
    text.should contain("██▄       ▄██    ▄██▄")
    text.should contain("██      ██    via #{Via::VERSION}")
    text.should contain("→ config     /etc/via/config.yaml")
    text.should contain("→ listening  :8080")
    text.should contain("→ upstream   localhost:3000")
    text.should end_with("\nready\n")
  end

  it "summarizes multiple targets and diagnostic mode" do
    output = IO::Memory.new

    Via::Console::Banner.render(
      output,
      config_path: "config.yaml",
      listen: ":8080",
      config: nil,
      debug: true
    )

    text = output.to_s
    text.should contain("→ state      configuration error")
    text.should contain("→ mode       debug")
  end

  it "lists every configured listener" do
    first = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 80),
      [Via::Routing::Route.new(nil, "/", URI.parse("http://localhost:3000"))]
    )
    second = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 443),
      [Via::Routing::Route.new(nil, "/", URI.parse("http://localhost:4000"))],
      tls: Via::Configuration::TLS.new("cert.pem", "key.pem")
    )
    output = IO::Memory.new

    Via::Console::Banner.render_many(
      output,
      config_path: "/etc/via/config",
      listeners: [
        {":80", first.as(Via::Configuration::Validated?)},
        {":443", second.as(Via::Configuration::Validated?)},
      ],
      debug: false
    )

    text = output.to_s
    text.should contain("→ listening  :80\n")
    text.should contain("→ listening  :443 (TLS)\n")
    text.should contain("→ routes     2\n")
  end

  it "summarizes direct response targets" do
    config = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 8080),
      [
        Via::Routing::Route.new(nil, "/admin", nil, nil, 403),
      ]
    )
    output = IO::Memory.new

    Via::Console::Banner.render(
      output,
      config_path: "config.yaml",
      listen: ":8080",
      config: config,
      debug: false
    )

    output.to_s.should contain("→ response   403")
  end

  it "shows configured logging settings" do
    config = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 8080),
      [
        Via::Routing::Route.new(
          nil,
          "/",
          URI.parse("http://localhost:3000")
        ),
      ],
      log_file: "/var/log/via.log",
      log_level: Via::Logging::Level::Warn
    )
    output = IO::Memory.new

    Via::Console::Banner.render(
      output,
      config_path: "config.yaml",
      listen: ":8080",
      config: config,
      debug: false
    )

    text = output.to_s
    text.should contain("→ log file   /var/log/via.log")
    text.should contain("→ log level  warn")
  end

  it "shows the CLI log level override" do
    config = Via::Configuration::Validated.new(
      Via::Configuration::ListenAddress.new("0.0.0.0", 8080),
      [
        Via::Routing::Route.new(
          nil,
          "/",
          URI.parse("http://localhost:3000")
        ),
      ],
      log_level: Via::Logging::Level::Debug
    )
    output = IO::Memory.new

    Via::Console::Banner.render(
      output,
      config_path: "config.yaml",
      listen: ":8080",
      config: config,
      debug: true,
      log_level_override: Via::Logging::Level::Error
    )

    text = output.to_s
    text.should contain("→ log level  error")
    text.should contain("→ mode       debug")
  end
end
