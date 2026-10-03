module Via::Configuration
  class Loader
    CONFIG_EXTENSIONS = {".yaml", ".yml"}

    def initialize(@path : String)
    end

    def load : Model
      models = load_all
      if models.size > 1
        raise Error.new(
          "Configuration directory #{@path} defines multiple listeners; load all listener configurations"
        )
      end
      models.first
    end

    def load_all : Array(Model)
      if File.directory?(@path)
        load_directory
      else
        [Model.load(@path)]
      end
    rescue ex : File::Error
      raise Error.new("Could not read configuration #{@path}: #{ex.message}")
    end

    private def load_directory : Array(Model)
      files = config_files
      if files.empty?
        raise Error.new("Configuration directory #{@path} contains no YAML files")
      end

      fragments = files.map { |file| Model.load(file) }
      groups = {} of ListenAddress => Array(Model)
      fragments.each do |fragment|
        next unless fragment.listen

        listen = Validator.new(fragment).validate_listen
        groups[listen] ||= [] of Model
        groups[listen] << fragment
      end

      if groups.size <= 1
        return [merge_fragments(fragments)]
      end

      if fragments.any?(&.listen.nil?)
        raise Error.new(
          "Every YAML file must declare listen when a configuration directory defines multiple listeners"
        )
      end

      groups.values.map { |group| merge_fragments(group) }
    end

    private def merge_fragments(fragments : Array(Model)) : Model
      listens = fragments.compact_map(&.listen)
      hosts = fragments.compact_map(&.host)
      debug_values = fragments.compact_map(&.debug)
      log_files = fragments.compact_map(&.log_file)
      log_levels = fragments.compact_map(&.log_level)
      proxy_passes = fragments.compact_map(&.proxy_pass)
      routes = fragments.flat_map { |fragment| fragment.routes || [] of Route }
      tls_configs = fragments.compact_map(&.tls)
      config_files = fragments.compact_map(&.config_file).uniq

      normalized_listens = fragments.compact_map do |fragment|
        Validator.new(fragment).validate_listen if fragment.listen
      end.uniq
      if normalized_listens.size > 1
        raise Error.new(
          "Listener fragments must use the same listen address"
        )
      end

      if hosts.size > 1
        raise Error.new(
          "Listener fragments must declare host at most once, found #{hosts.size}"
        )
      end

      if debug_values.size > 1
        raise Error.new(
          "Configuration directory must declare debug at most once, found #{debug_values.size}"
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
        host: hosts.first?,
        debug: debug_values.first?,
        log_file: log_files.first?,
        log_level: log_levels.first?,
        proxy_pass: proxy_passes.first?,
        routes: routes.empty? ? nil : routes,
        tls: tls_configs.first?,
        config_file: config_files.size == 1 ? config_files.first : @path
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
