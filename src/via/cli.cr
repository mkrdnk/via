require "option_parser"

module Via
  class CLI
    DEFAULT_CONFIG_PATH = "/etc/via/"

    def self.run(args = ARGV, output : IO = STDOUT, error : IO = STDERR) : Int32
      command = args.first?
      command_args = args.size > 1 ? args[1, args.size - 1] : [] of String

      case command
      when "run"
        run_server(command_args, output, error)
      when "check"
        check_configuration(command_args, output, error)
      when "-h", "--help"
        if command_args.empty?
          output.puts help
          0
        else
          reject_unexpected_arguments(command_args, error, help)
        end
      when "--version"
        if command_args.empty?
          output.puts "via #{VERSION}"
          0
        else
          reject_unexpected_arguments(command_args, error, help)
        end
      when nil
        error.puts "A command is required."
        error.puts help
        2
      else
        error.puts "Unknown command: #{command}"
        error.puts help
        2
      end
    rescue ex : Configuration::Error
      error.puts "Configuration error: #{ex.message}"
      1
    rescue ex : Socket::Error
      error.puts "Could not start Via: #{ex.message}"
      1
    end

    private def self.run_server(args : Array(String), output : IO, error : IO) : Int32
      config_path = DEFAULT_CONFIG_PATH
      debug = false
      log_level_override = nil.as(Logging::Level?)
      requested_exit = false
      exit_code = 0

      parser = OptionParser.new do |options|
        options.banner = "Usage: via run [options]"
        options.on("-c PATH", "--config=PATH", "Configuration file or directory (default: #{DEFAULT_CONFIG_PATH})") do |path|
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

      path = config_path
      models = Configuration::Loader.new(path).load_all
      validators = models.map { |model| Configuration::Validator.new(model) }
      listens = validators.map(&.validate_listen)
      reject_duplicate_listens(listens)
      states = [] of Runtime::State
      validated_configs = [] of Configuration::Validated?
      begin
        models.each_with_index do |model, index|
          configured_debug = model.debug == true
          state = Runtime::State.new(
            error,
            debug,
            log_level_override,
            configured_debug: configured_debug
          )
          states << state
          begin
            validated = validators[index].validate
            state.apply(validated, source: validated.config_file || path)
            validated_configs << validated
          rescue ex : Configuration::Error
            raise ex unless (debug || configured_debug) && model.tls.nil?
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
        configuration_debug: models.any? { |model| model.debug == true },
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
    end

    private def self.check_configuration(
      args : Array(String),
      output : IO,
      error : IO,
    ) : Int32
      config_path = DEFAULT_CONFIG_PATH
      requested_exit = false
      exit_code = 0

      parser = OptionParser.new do |options|
        options.banner = "Usage: via check [options]"
        options.on("-c PATH", "--config=PATH", "Configuration file or directory (default: #{DEFAULT_CONFIG_PATH})") do |path|
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

      models = Configuration::Loader.new(config_path).load_all
      validators = models.map { |model| Configuration::Validator.new(model) }
      listens = validators.map(&.validate_listen)
      reject_duplicate_listens(listens)
      logger = Logging::Logger.new(error)
      begin
        validators.each do |validator|
          validated = validator.validate
          TLS::ContextBuilder.build(validated.tls)
          logger.configure(
            validated.log_file,
            validated.debug ? Logging::Level::Debug : validated.log_level || Logging::Level::Info
          )
        end
      ensure
        logger.close
      end

      output.puts "Configuration is valid: #{config_path}"
      0
    end

    private def self.help : String
      <<-TEXT
      Usage: via COMMAND [options]

      Commands:
        run    Start Via (default configuration: #{DEFAULT_CONFIG_PATH})
        check  Validate configuration without starting Via

      Global options:
        --version  Show Via version
        -h, --help Show this help

      Run "via COMMAND --help" for command options.
      TEXT
    end

    private def self.reject_unexpected_arguments(
      arguments : Array(String),
      error : IO,
      usage : String,
    ) : Int32
      error.puts "Unexpected argument#{arguments.size == 1 ? "" : "s"}: #{arguments.join(' ')}"
      error.puts usage
      2
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
