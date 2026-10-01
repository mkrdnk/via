module Via
  class ConfigLoader
    CONFIG_EXTENSIONS = {".yaml", ".yml"}

    def initialize(@path : String)
    end

    def load : Config
      if File.directory?(@path)
        load_directory
      else
        Config.load(@path)
      end
    rescue ex : File::Error
      raise ConfigurationError.new("Could not read configuration #{@path}: #{ex.message}")
    end

    private def load_directory : Config
      files = config_files
      if files.empty?
        raise ConfigurationError.new("Configuration directory #{@path} contains no YAML files")
      end

      fragments = files.map { |file| Config.load(file) }
      listens = fragments.compact_map(&.listen)
      proxy_passes = fragments.compact_map(&.proxy_pass)
      routes = fragments.flat_map { |fragment| fragment.routes || [] of RouteConfig }

      if listens.size > 1
        raise ConfigurationError.new(
          "Configuration directory must declare listen exactly once, found #{listens.size}"
        )
      end

      if proxy_passes.size > 1
        raise ConfigurationError.new(
          "Configuration directory must declare proxy_pass at most once, found #{proxy_passes.size}"
        )
      end

      Config.new(
        listen: listens.first?,
        proxy_pass: proxy_passes.first?,
        routes: routes.empty? ? nil : routes
      )
    end

    private def config_files : Array(String)
      Dir.children(@path)
        .select { |name| CONFIG_EXTENSIONS.includes?(File.extname(name).downcase) }
        .sort!
        .map { |name| File.join(@path, name) }
        .select { |path| File.file?(path) }
    end
  end
end
