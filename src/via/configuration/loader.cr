module Via::Configuration
  class Loader
    CONFIG_EXTENSIONS = {".yaml", ".yml"}

    def initialize(@path : String)
    end

    def load : Model
      if File.directory?(@path)
        load_directory
      else
        Model.load(@path)
      end
    rescue ex : File::Error
      raise Error.new("Could not read configuration #{@path}: #{ex.message}")
    end

    private def load_directory : Model
      files = config_files
      if files.empty?
        raise Error.new("Configuration directory #{@path} contains no YAML files")
      end

      fragments = files.map { |file| Model.load(file) }
      listens = fragments.compact_map(&.listen)
      log_files = fragments.compact_map(&.log_file)
      log_levels = fragments.compact_map(&.log_level)
      proxy_passes = fragments.compact_map(&.proxy_pass)
      routes = fragments.flat_map { |fragment| fragment.routes || [] of Route }
      tls_configs = fragments.compact_map(&.tls)

      if listens.size > 1
        raise Error.new(
          "Configuration directory must declare listen exactly once, found #{listens.size}"
        )
      end

      if log_files.size > 1
        raise Error.new(
          "Configuration directory must declare log_file at most once, found #{log_files.size}"
        )
      end

      if log_levels.size > 1
        raise Error.new(
          "Configuration directory must declare log_level at most once, found #{log_levels.size}"
        )
      end

      if proxy_passes.size > 1
        raise Error.new(
          "Configuration directory must declare proxy_pass at most once, found #{proxy_passes.size}"
        )
      end

      if tls_configs.size > 1
        raise Error.new(
          "Configuration directory must declare tls at most once, found #{tls_configs.size}"
        )
      end

      Model.new(
        listen: listens.first?,
        log_file: log_files.first?,
        log_level: log_levels.first?,
        proxy_pass: proxy_passes.first?,
        routes: routes.empty? ? nil : routes,
        tls: tls_configs.first?
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
