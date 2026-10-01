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
end
