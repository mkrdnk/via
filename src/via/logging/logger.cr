module Via::Logging
  class Logger
    def initialize(@output : IO = STDERR, @debug_enabled : Bool = false)
      @mutex = Mutex.new
    end

    def debug(event : String, **fields) : Nil
      return unless @debug_enabled
      write("debug", event, fields)
    end

    def info(event : String, **fields) : Nil
      write("info", event, fields)
    end

    def warn(event : String, **fields) : Nil
      write("warn", event, fields)
    end

    def error(event : String, **fields) : Nil
      write("error", event, fields)
    end

    private def write(level : String, event : String, fields) : Nil
      line = String.build do |io|
        io << "time=" << Time.utc.to_rfc3339(fraction_digits: 3)
        io << " level=" << level
        io << " event=" << event
        fields.each do |key, value|
          io << ' ' << key << '='
          append_value(io, value)
        end
      end

      @mutex.synchronize do
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
