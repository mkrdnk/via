module Via::Configuration
  class Reloader
    @dependencies : Array(String)

    def initialize(
      @path : String,
      @listen : ListenAddress,
      tls : TLS?,
      @state : Runtime::State,
      poll_interval : Time::Span = Watcher::DEFAULT_POLL_INTERVAL,
      debounce : Time::Span = Watcher::DEFAULT_DEBOUNCE,
    )
      @tls_enabled = !tls.nil?
      @dependency_mutex = Mutex.new
      @dependencies = tls_paths(tls)
      @watcher = Watcher.new(
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
      model = Loader.new(@path).load
      update_dependencies(model.tls)
      config = model.validate
      if config.listen != @listen
        raise Error.new("listen cannot be changed during hot reload")
      end
      if !config.tls.nil? != @tls_enabled
        raise Error.new("TLS cannot be enabled or disabled during hot reload")
      end

      @state.apply(config, source: config.config_file || @path, reloaded: true)
      true
    rescue ex : Error
      @state.reject(@path, ex)
      false
    end

    private def dependency_paths : Array(String)
      @dependency_mutex.synchronize { @dependencies.dup }
    end

    private def update_dependencies(tls : TLS?) : Nil
      paths = tls_paths(tls)
      @dependency_mutex.synchronize { @dependencies = paths }
    end

    private def tls_paths(tls : TLS?) : Array(String)
      tls ? [tls.cert, tls.key] : [] of String
    end
  end
end
