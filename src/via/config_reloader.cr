module Via
  class ConfigReloader
    def initialize(
      @path : String,
      @listen : ListenAddress,
      @state : RuntimeState,
      @log : IO = STDOUT,
      poll_interval : Time::Span = ConfigWatcher::DEFAULT_POLL_INTERVAL,
      debounce : Time::Span = ConfigWatcher::DEFAULT_DEBOUNCE,
    )
      @watcher = ConfigWatcher.new(@path, poll_interval, debounce)
    end

    def start : Nil
      @watcher.start { reload }
    end

    def stop : Nil
      @watcher.stop
    end

    def reload : Bool
      config = ConfigLoader.new(@path).load.validate
      if config.listen != @listen
        raise ConfigurationError.new("listen cannot be changed during hot reload")
      end

      @state.apply(config)
      @log.puts "Configuration reloaded"
      true
    rescue ex : ConfigurationError
      @state.reject(@path, ex)
      false
    end
  end
end
