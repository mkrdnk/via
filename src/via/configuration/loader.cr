module Via::Configuration
  class Loader
    CONFIG_EXTENSIONS = {".yaml", ".yml"}

    def initialize(@path : String)
    end

    def load : Model
      models = load_all
      if models.empty?
        raise Error.new("Configuration #{@path} has no enabled listeners")
      end
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
        model = Model.load(@path)
        model.enable ? [model] : [] of Model
      end
    rescue ex : File::Error
      raise Error.new("Could not read configuration #{@path}: #{ex.message}")
    end

    private def load_directory : Array(Model)
      files = config_files
      if files.empty?
        raise Error.new("Configuration directory #{@path} contains no YAML files")
      end

      fragments = files.map { |file| Model.load(file) }.select(&.enable)
      return [] of Model if fragments.empty?

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
      timeout_configs = fragments.compact_map(&.timeouts)
      shutdown_configs = fragments.compact_map(&.shutdown)
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

      debug = single_fragment_value(debug_values, "debug")
      log_file = single_fragment_value(log_files, "log_file")
      log_level = single_fragment_value(log_levels, "log_level")
      proxy_pass = single_fragment_value(proxy_passes, "proxy_pass")
      tls = single_fragment_value(tls_configs, "tls")
      timeouts = single_fragment_value(timeout_configs, "timeouts")
      shutdown = single_fragment_value(shutdown_configs, "shutdown")

      Model.new(
        listen: listens.first?,
        host: hosts.first?,
        debug: debug,
        log_file: log_file,
        log_level: log_level,
        proxy_pass: proxy_pass,
        routes: routes.empty? ? nil : routes,
        tls: tls,
        timeouts: timeouts,
        shutdown: shutdown,
        config_file: config_files.size == 1 ? config_files.first : @path
      )
    end

    private def single_fragment_value(values : Array(T), field : String) : T? forall T
      if values.size > 1
        raise Error.new(
          "Configuration directory must declare #{field} at most once, found #{values.size}"
        )
      end

      values.first?
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
