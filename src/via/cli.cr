require "option_parser"

module Via
  class CLI
    def self.run(args = ARGV, output : IO = STDOUT, error : IO = STDERR) : Int32
      config_path = nil
      debug = false
      requested_exit = false
      exit_code = 0

      parser = OptionParser.new do |options|
        options.banner = "Usage: via -c CONFIG"
        options.on("-c PATH", "--config=PATH", "Path to the YAML configuration") do |path|
          config_path = path
        end
        options.on("--debug", "Show diagnostics and verbose proxy logs") do
          debug = true
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

      model = Configuration::Loader.new(path).load
      validator = Configuration::Validator.new(model)
      listen = validator.validate_listen
      state = Runtime::State.new(error, debug)
      tls_enabled = false
      tls = nil
      validated = nil

      begin
        validated = validator.validate
        state.apply(validated)
        tls = validated.tls
        tls_enabled = !tls.nil?
      rescue ex : Configuration::Error
        raise ex unless debug && model.tls.nil?
        state.reject(path, ex)
      end

      server = Server.new(listen, state, tls_enabled)
      server.bind
      Console::Banner.render(
        output,
        config_path: path,
        listen: model.listen.not_nil!,
        config: validated,
        debug: debug
      )

      reloader = Configuration::Reloader.new(path, listen, tls, state, output)
      reloader.start

      Signal::INT.trap { server.close }
      Signal::TERM.trap { server.close }
      begin
        server.listen
      ensure
        reloader.stop
        state.close
      end
      0
    rescue ex : Configuration::Error
      error.puts "Configuration error: #{ex.message}"
      1
    rescue ex : Socket::Error
      error.puts "Could not start Via: #{ex.message}"
      1
    end
  end
end
