module Via::Configuration
  class GroupReloader
    private record Target,
      tls_enabled : Bool,
      state : Runtime::State

    @dependencies : Array(String)

    def initialize(
      @path : String,
      listens : Array(ListenAddress),
      tls_enabled : Array(Bool),
      states : Array(Runtime::State),
      poll_interval : Time::Span = Watcher::DEFAULT_POLL_INTERVAL,
      debounce : Time::Span = Watcher::DEFAULT_DEBOUNCE,
    )
      unless listens.size == tls_enabled.size && listens.size == states.size
        raise ArgumentError.new("Listener reload targets must have matching sizes")
      end

      @targets = {} of ListenAddress => Target
      listens.each_with_index do |listen, index|
        if @targets.has_key?(listen)
          raise Error.new("Duplicate listen address: #{listen.host}:#{listen.port}")
        end
        @targets[listen] = Target.new(tls_enabled[index], states[index])
      end

      @dependency_mutex = Mutex.new
      @dependencies = [] of String
      @watcher = Watcher.new(
        @path,
        poll_interval,
        debounce,
        -> { dependency_paths }
      )
    end

    def set_dependencies(models : Enumerable(Model)) : Nil
      update_dependencies(models)
    end

    def start : Nil
      @watcher.start { reload }
    end

    def stop : Nil
      @watcher.stop
    end

    def reload : Bool
      models = Loader.new(@path).load_all
      update_dependencies(models)
      configs = models.map(&.validate)
      replacements = index_configs(configs)

      unless replacements.keys.to_set == @targets.keys.to_set
        raise Error.new("Listeners cannot be added, removed, or changed during hot reload")
      end

      replacements.each do |listen, config|
        target = @targets[listen]
        if !config.tls.nil? != target.tls_enabled
          raise Error.new("TLS cannot be enabled or disabled during hot reload")
        end
      end

      replacements.each do |listen, config|
        source = config.config_file || @path
        @targets[listen].state.apply(config, source: source, reloaded: true)
      end
      true
    rescue ex : Error
      @targets.each_value { |target| target.state.reject(@path, ex) }
      false
    end

    private def index_configs(
      configs : Enumerable(Validated),
    ) : Hash(ListenAddress, Validated)
      indexed = {} of ListenAddress => Validated
      configs.each do |config|
        if indexed.has_key?(config.listen)
          listen = config.listen
          raise Error.new("Duplicate listen address: #{listen.host}:#{listen.port}")
        end
        indexed[config.listen] = config
      end
      indexed
    end

    private def dependency_paths : Array(String)
      @dependency_mutex.synchronize { @dependencies.dup }
    end

    private def update_dependencies(models : Enumerable(Model)) : Nil
      paths = models.compact_map(&.tls).flat_map { |tls| [tls.cert, tls.key] }
      @dependency_mutex.synchronize { @dependencies = paths }
    end
  end
end
