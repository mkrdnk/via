module Via::Logging
  class Logger
    @output : IO
    @level : Level
    @owns_output : Bool

    def initialize(@base_output : IO = STDERR, debug_enabled : Bool = false)
      @mutex = Mutex.new
      @output = @base_output
      @level = debug_enabled ? Level::Debug : Level::Info
      @owns_output = false
    end

    def debug(event : String, **fields) : Nil
      write(Level::Debug, event, fields)
    end

    def info(event : String, **fields) : Nil
      write(Level::Info, event, fields)
    end

    def warn(event : String, **fields) : Nil
      write(Level::Warn, event, fields)
    end

    def error(event : String, **fields) : Nil
      write(Level::Error, event, fields)
    end

    def configure(path : String?, level : Level) : Nil
      replacement = path ? open_file(path) : @base_output
      owns_replacement = !path.nil?

      @mutex.synchronize do
        previous = @output
        owned_previous = @owns_output
        @output = replacement
        @level = level
        @owns_output = owns_replacement
        close_output(previous) if owned_previous
      end
    end

    def close : Nil
      @mutex.synchronize do
        close_output(@output) if @owns_output
        @output = @base_output
        @owns_output = false
      end
    end

    private def open_file(path : String) : File
      File.open(path, "a")
    rescue ex : File::Error
      raise Configuration::Error.new("Could not open log_file #{path}: #{ex.message}")
    end

    private def close_output(output : IO) : Nil
      output.close
    rescue IO::Error
      # Logging failures must never interrupt runtime reconfiguration or shutdown.
    end

    private def write(level : Level, event : String, fields) : Nil
      @mutex.synchronize do
        return if level.value < @level.value

        line = String.build do |io|
          io << "time=" << Time.utc.to_rfc3339(fraction_digits: 3)
          io << " level=" << level.label
          io << " event=" << event
          fields.each do |key, value|
            io << ' ' << key << '='
            append_value(io, value)
          end
        end

        @output.puts(line)
        @output.flush
      end
    rescue IO::Error
      # Logging must never interrupt request processing.
    end

    private def append_value(io : IO, value : String) : Nil
      value.inspect(io)
    end

    private def append_value(io : IO, value : Nil) : Nil
      io << "null"
    end

    private def append_value(io : IO, value) : Nil
      io << value
    end
  end
end
