require "./spec_helper"

describe Via::Configuration::Loader do
  it "preserves duplicate fragment field errors" do
    duplicate_fields = [
      {"debug", "debug: true", "debug: false"},
      {"log_file", "log_file: first.log", "log_file: second.log"},
      {"log_level", "log_level: INFO", "log_level: WARN"},
      {"proxy_pass", "proxy_pass: http://localhost:3000", "proxy_pass: http://localhost:4000"},
      {"tls", "tls:\n  cert: first.pem\n  key: first.key", "tls:\n  cert: second.pem\n  key: second.key"},
      {"timeouts", "timeouts:\n  connect: 1s", "timeouts:\n  read: 2s"},
      {"shutdown", "shutdown:\n  websocket_timeout: 1s", "shutdown:\n  websocket_timeout: 2s"},
    ]

    duplicate_fields.each do |field, first_value, second_value|
      with_temp_directory do |directory|
        File.write(File.join(directory, "01-listener.yaml"), <<-YAML)
          listen: ":8080"
          #{first_value}
          YAML
        File.write(File.join(directory, "02-duplicate.yaml"), "#{second_value}\n")

        expect_raises(
          Via::ConfigurationError,
          "Configuration directory must declare #{field} at most once, found 2"
        ) do
          Via::ConfigLoader.new(directory).load
        end
      end
    end
  end
end
