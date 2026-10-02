module Via::Console
  module Banner
    extend self

    LOGO = <<-TEXT
      ██▄       ▄██    ▄██▄
       ▀██▄   ▄██▀    ██  ██
         ██▄ ▄██     ██    ██
          ▀███▀     ██      ██
      TEXT

    def render(
      output : IO,
      *,
      config_path : String,
      listen : String,
      config : Configuration::Validated?,
      debug : Bool,
      log_level_override : Logging::Level? = nil,
    ) : Nil
      render_many(
        output,
        config_path: config_path,
        listeners: [{listen, config}],
        debug: debug,
        log_level_override: log_level_override
      )
    end

    def render_many(
      output : IO,
      *,
      config_path : String,
      listeners : Array(Tuple(String, Configuration::Validated?)),
      debug : Bool,
      log_level_override : Logging::Level? = nil,
    ) : Nil
      logo(output)
      output << "    via " << Via::VERSION << "\n\n"

      row(output, "config", config_path)
      listeners.each do |listen, config|
        row(output, "listening", listening_value(listen, config))
      end

      configs = [] of Configuration::Validated
      listeners.each do |_, config|
        configs << config if config
      end
      configs.each { |config| logging(output, config, debug, log_level_override) }
      targets(output, configs)
      if listeners.any? { |_, config| config.nil? }
        row(output, "state", "configuration error")
      end
      row(output, "mode", "debug") if debug
      output << "\nready\n"
    end

    private def logo(output : IO) : Nil
      lines = LOGO.lines
      lines[0...-1].each { |line| output << line << '\n' }
      output << lines.last
    end

    private def row(output : IO, label : String, value : String) : Nil
      output << "→ " << label.ljust(11) << value << '\n'
    end

    private def listening_value(
      listen : String,
      config : Configuration::Validated?,
    ) : String
      config.try(&.tls) ? "#{listen} (TLS)" : listen
    end

    private def logging(
      output : IO,
      config : Configuration::Validated?,
      debug : Bool,
      log_level_override : Logging::Level?,
    ) : Nil
      return unless config

      config.log_file.try { |path| row(output, "log file", path) }
      if level = log_level_override
        row(output, "log level", level.label)
      elsif configured_level = config.log_level
        level = debug ? Logging::Level::Debug : configured_level
        row(output, "log level", level.label)
      elsif config.log_file
        row(output, "log level", debug ? "debug" : "info")
      end
    end

    private def targets(
      output : IO,
      configs : Enumerable(Configuration::Validated),
    ) : Nil
      routes = configs.flat_map(&.routes)
      row(output, "routes", routes.size.to_s) if routes.size > 1

      upstreams = routes.compact_map(&.upstream).uniq
      upstreams.each do |upstream|
        value = upstream.scheme == "https" ? upstream.to_s : upstream.authority.not_nil!
        row(output, "upstream", value)
      end

      static_roots = routes.compact_map(&.static_target).map(&.root).uniq
      static_roots.each { |root| row(output, "static", root) }

      response_statuses = routes.compact_map(&.response_status).uniq
      response_statuses.each { |status| row(output, "response", status.to_s) }
    end
  end
end
