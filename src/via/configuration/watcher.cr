require "atomic"

module Via::Configuration
  class Watcher
    DEFAULT_POLL_INTERVAL = 100.milliseconds
    DEFAULT_DEBOUNCE      = 200.milliseconds

    def initialize(
      @path : String,
      @poll_interval : Time::Span = DEFAULT_POLL_INTERVAL,
      @debounce : Time::Span = DEFAULT_DEBOUNCE,
      @additional_paths : (-> Array(String))? = nil,
    )
      @stopped = Atomic(Bool).new(false)
    end

    def start(&on_change : ->) : Nil
      spawn watch(on_change)
    end

    def stop : Nil
      @stopped.set(true)
    end

    private def watch(on_change : ->) : Nil
      last_fingerprint = fingerprint
      changed_at = nil

      until @stopped.get
        sleep @poll_interval
        break if @stopped.get

        current_fingerprint = fingerprint

        if current_fingerprint != last_fingerprint
          last_fingerprint = current_fingerprint
          changed_at = Time.instant
        elsif timestamp = changed_at
          if Time.instant - timestamp >= @debounce
            changed_at = nil
            stable_fingerprint = last_fingerprint
            on_change.call
            after_reload = fingerprint
            if after_reload != stable_fingerprint
              last_fingerprint = after_reload
              changed_at = Time.instant
            end
          end
        end
      end
    end

    private def fingerprint : UInt64
      paths = watched_config_paths
      if additional_paths = @additional_paths
        paths.concat(additional_paths.call)
      end
      paths = paths.uniq!.sort!

      paths.compact_map do |path|
        if info = File.info?(path)
          {path, info.size, info.modification_time.to_unix_ns}
        end
      end.hash
    rescue File::Error
      {@path, "unavailable"}.hash
    end

    private def watched_config_paths : Array(String)
      if File.directory?(@path)
        Dir.children(@path)
          .select { |name| Loader::CONFIG_EXTENSIONS.includes?(File.extname(name).downcase) }
          .map { |name| File.join(@path, name) }
      else
        [@path]
      end
    end
  end
end
