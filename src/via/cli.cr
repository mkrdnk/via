require "option_parser"

module Via
  class CLI
    def self.run(args = ARGV, output : IO = STDOUT, error : IO = STDERR) : Int32
      config_path = nil
      debug = false
      log_level_override = nil.as(Logging::Level?)
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
        options.on("--log-level=LEVEL", "Override the configured log level") do |value|
          if level = Logging::Level.parse_config(value)
            log_level_override = level
          else
            error.puts "Invalid log level: #{value}"
            error.puts "Expected DEBUG, INFO, WARN, or ERROR."
            requested_exit = true
            exit_code = 2
          end
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

      models = Configuration::Loader.new(path).load_all
      validators = models.map { |model| Configuration::Validator.new(model) }
      listens = validators.map(&.validate_listen)
      reject_duplicate_listens(listens)
      states = [] of Runtime::State
      validated_configs = [] of Configuration::Validated?
      begin
        models.each_with_index do |model, index|
          state = Runtime::State.new(error, debug, log_level_override)
          states << state
          begin
            validated = validators[index].validate
            state.apply(validated, source: validated.config_file || path)
            validated_configs << validated
          rescue ex : Configuration::Error
            raise ex unless debug && model.tls.nil?
            state.reject(model.config_file || path, ex)
            validated_configs << nil
          end
        end
      rescue ex
        states.each(&.close)
        raise ex
      end

      servers = listens.map_with_index do |listen, index|
        Server.new(listen, states[index], !models[index].tls.nil?)
      end
      server_group = ServerGroup.new(servers)
      server_group.bind

      banner_listeners = [] of Tuple(String, Configuration::Validated?)
      models.each_with_index do |model, index|
        banner_listeners << {model.listen.not_nil!, validated_configs[index]}
      end
      Console::Banner.render_many(
        output,
        config_path: path,
        listeners: banner_listeners,
        debug: debug,
        log_level_override: log_level_override
      )

      reloader = Configuration::GroupReloader.new(
        path,
        listens,
        models.map { |model| !model.tls.nil? },
        states
      )
      reloader.set_dependencies(models)
      reloader.start

      Signal::INT.trap { server_group.close }
      Signal::TERM.trap { server_group.close }
      begin
        server_group.listen
      ensure
        reloader.stop
        server_group.close
      end
      0
    rescue ex : Configuration::Error
      error.puts "Configuration error: #{ex.message}"
      1
    rescue ex : Socket::Error
      error.puts "Could not start Via: #{ex.message}"
      1
    end

    private def self.reject_duplicate_listens(
      listens : Enumerable(Configuration::ListenAddress),
    ) : Nil
      seen = Set(Configuration::ListenAddress).new
      listens.each do |listen|
        unless seen.add?(listen)
          raise Configuration::Error.new(
            "Duplicate listen address: #{listen.host}:#{listen.port}"
          )
        end
      end
    end
  end
end
