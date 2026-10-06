module Via::Runtime
  # Tracks upgraded connections independently from configuration generations so
  # hot reloads do not interrupt them and shutdown can apply one grace period.
  class WebSocketRegistry
    class Entry
      getter upstream : IO
      property downstream : IO?

      def initialize(@upstream : IO)
        @downstream = nil
      end
    end

    def initialize
      @mutex = Mutex.new
      @entries = Set(Entry).new
      @draining = false
      @closed = false
      @drained = Channel(Nil).new(1)
    end

    def reserve(upstream : IO) : Entry
      entry = Entry.new(upstream)
      close = @mutex.synchronize do
        if @closed
          true
        else
          @entries << entry
          false
        end
      end
      close(upstream) if close
      entry
    end

    def attach(entry : Entry, downstream : IO) : Bool
      attached = @mutex.synchronize do
        if @closed || !@entries.includes?(entry)
          false
        else
          entry.downstream = downstream
          true
        end
      end
      close(downstream) unless attached
      attached
    end

    def release(entry : Entry) : Nil
      notify = @mutex.synchronize do
        @entries.delete(entry)
        @draining && @entries.empty?
      end
      notify_drained if notify
    end

    def drain(timeout : Time::Span) : Nil
      empty = @mutex.synchronize do
        @draining = true
        @entries.empty?
      end

      unless empty
        select
        when @drained.receive
        when timeout(timeout)
        end
      end

      force_close
    end

    def close : Nil
      force_close
    end

    private def force_close : Nil
      entries = @mutex.synchronize do
        return if @closed

        @closed = true
        active = @entries
        @entries = Set(Entry).new
        active
      end

      entries.each do |entry|
        close(entry.downstream)
        close(entry.upstream)
      end
      notify_drained
    end

    private def notify_drained : Nil
      select
      when @drained.send(nil)
      else
      end
    end

    private def close(io : IO?) : Nil
      io.try { |value| value.close unless value.closed? }
    rescue
      # A peer can close the same transport concurrently.
    end
  end
end
