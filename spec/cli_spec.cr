require "./spec_helper"

describe Via::CLI do
  it "preserves command help option order" do
    {
      "run"   => ["-c PATH, --config=PATH", "--debug", "--log-level=LEVEL", "--version", "-h, --help"],
      "check" => ["-c PATH, --config=PATH", "--version", "-h, --help"],
    }.each do |command, option_labels|
      output = IO::Memory.new

      Via::CLI.run([command, "--help"], output, IO::Memory.new).should eq(0)

      rendered = output.to_s
      rendered.should start_with("Usage: via #{command} [options]\n")
      previous_position = -1
      option_labels.each do |label|
        position = rendered.index(label).not_nil!
        position.should be > previous_position
        previous_position = position
      end
    end
  end

  it "processes version and help together in option order" do
    ["run", "check"].each do |command|
      output = IO::Memory.new

      Via::CLI.run([command, "--version", "--help"], output, IO::Memory.new).should eq(0)

      output.to_s.should start_with("via #{Via::VERSION}\nUsage: via #{command} [options]\n")
    end
  end

  it "preserves common parser errors and their exit codes" do
    ["run", "check"].each do |command|
      missing_value_output = IO::Memory.new
      missing_value_error = IO::Memory.new

      Via::CLI.run([command, "-c"], missing_value_output, missing_value_error).should eq(2)
      missing_value_output.to_s.should be_empty
      missing_value_error.to_s.should start_with("Missing value for -c\nUsage: via #{command} [options]\n")

      unknown_option_output = IO::Memory.new
      unknown_option_error = IO::Memory.new
      Via::CLI.run([command, "--unknown", "argument"], unknown_option_output, unknown_option_error).should eq(2)
      unknown_option_output.to_s.should be_empty
      rendered_error = unknown_option_error.to_s
      rendered_error.should start_with("Unexpected arguments: --unknown argument\nUsage: via #{command} [options]\n")
      rendered_error.index("Unknown option: --unknown\n").not_nil!.should be > 0
      rendered_error.scan("Usage: via #{command} [options]\n").size.should eq(2)
    end
  end

  it "does not let help or version clear an invalid log level exit code" do
    [
      ["run", "--log-level=invalid", "--help", "--version"],
      ["run", "--version", "--help", "--log-level=invalid"],
    ].each do |arguments|
      output = IO::Memory.new
      error = IO::Memory.new

      Via::CLI.run(arguments, output, error).should eq(2)
      output.to_s.should contain("Usage: via run [options]\n")
      output.to_s.should contain("via #{Via::VERSION}\n")
      error.to_s.should eq("Invalid log level: invalid\nExpected DEBUG, INFO, WARN, or ERROR.\n")
    end
  end
end
