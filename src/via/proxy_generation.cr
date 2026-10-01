module Via
  # :nodoc:
  class ProxyGeneration
    def initialize(routes : Array(Route), log : IO, debug : Bool, scheme : String)
      @proxy = Proxy.new(routes, log, debug, scheme)
      @mutex = Mutex.new
      @active_requests = 0
      @retired = false
      @closed = false
    end

    def acquire : Nil
      @mutex.synchronize do
        raise "cannot acquire a retired proxy generation" if @retired
        @active_requests += 1
      end
    end

    def call(context : HTTP::Server::Context) : Nil
      @proxy.call(context)
    end

    def release : Nil
      close = @mutex.synchronize do
        @active_requests -= 1
        close_if_retired_and_idle
      end
      @proxy.close if close
    end

    def retire : Nil
      close = @mutex.synchronize do
        @retired = true
        close_if_retired_and_idle
      end
      @proxy.close if close
    end

    private def close_if_retired_and_idle : Bool
      should_close = @retired && @active_requests == 0 && !@closed
      @closed = true if should_close

      should_close
    end
  end
end
