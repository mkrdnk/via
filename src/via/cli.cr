require "option_parser"

module Via
  class CLI
    def self.run(args = ARGV, output : IO = STDOUT, error : IO = STDERR) : Int32
      config_path = nil
      requested_exit = false
      exit_code = 0

      parser = OptionParser.new do |options|
        options.banner = "Usage: via -c CONFIG"
        options.on("-c PATH", "--config=PATH", "Path to the YAML configuration") do |path|
          config_path = path
        end
        options.on("--version", "Show Via version") do
          output.puts "via #{VERSION}"
          requested_exit = true
        end
        options.on("-h", "--help", "Show this help") do
          output.puts options
          requested_exit = true
        end
        options.invalid_option do |flag|
          error.puts "Unknown option: #{flag}"
          error.puts options
          requested_exit = true
          exit_code = 2
        end
        options.missing_option do |flag|
          error.puts "Missing value for #{flag}"
          error.puts options
          requested_exit = true
          exit_code = 2
        end
        options.unknown_args do |before_dash, after_dash|
          arguments = before_dash + after_dash
          next if arguments.empty?

          error.puts "Unexpected argument#{arguments.size == 1 ? "" : "s"}: #{arguments.join(' ')}"
          error.puts options
          requested_exit = true
          exit_code = 2
        end
      end

      parser.parse(args)
      return exit_code if requested_exit

      unless path = config_path
        error.puts "Configuration is required. Use -c PATH or --config=PATH."
        error.puts parser
        return 2
      end

      config = Config.load(path).validate
      server = Server.new(config, error)
      address = server.bind
      output.puts "Via #{VERSION} listening on http://#{address}"

      Signal::INT.trap { server.close }
      Signal::TERM.trap { server.close }
      server.listen
      0
    rescue ex : ConfigurationError
      error.puts "Configuration error: #{ex.message}"
      1
    rescue ex : Socket::Error
      error.puts "Could not start Via: #{ex.message}"
      1
    end
  end
end
