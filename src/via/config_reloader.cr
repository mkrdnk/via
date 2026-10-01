module Via
  class ConfigReloader
    @dependencies : Array(String)

    def initialize(
      @path : String,
      @listen : ListenAddress,
      tls : TlsConfig?,
      @state : RuntimeState,
      @log : IO = STDOUT,
      poll_interval : Time::Span = ConfigWatcher::DEFAULT_POLL_INTERVAL,
      debounce : Time::Span = ConfigWatcher::DEFAULT_DEBOUNCE,
    )
      @tls_enabled = !tls.nil?
      @dependency_mutex = Mutex.new
      @dependencies = tls_paths(tls)
      @watcher = ConfigWatcher.new(
        @path,
        poll_interval,
        debounce,
        -> { dependency_paths }
      )
    end

    def start : Nil
      @watcher.start { reload }
    end

    def stop : Nil
      @watcher.stop
    end

    def reload : Bool
      model = ConfigLoader.new(@path).load
      update_dependencies(model.tls)
      config = model.validate
      if config.listen != @listen
        raise ConfigurationError.new("listen cannot be changed during hot reload")
      end
      if !config.tls.nil? != @tls_enabled
        raise ConfigurationError.new("TLS cannot be enabled or disabled during hot reload")
      end

      @state.apply(config)
      @log.puts "Configuration reloaded"
      true
    rescue ex : ConfigurationError
      @state.reject(@path, ex)
      false
    end

    private def dependency_paths : Array(String)
      @dependency_mutex.synchronize { @dependencies.dup }
    end

    private def update_dependencies(tls : TlsConfig?) : Nil
      paths = tls_paths(tls)
      @dependency_mutex.synchronize { @dependencies = paths }
    end

    private def tls_paths(tls : TlsConfig?) : Array(String)
      tls ? [tls.cert, tls.key] : [] of String
    end
  end
end
