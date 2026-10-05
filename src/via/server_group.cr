require "wait_group"

module Via
  class ServerGroup
    def initialize(@servers : Array(Server))
      if @servers.empty?
        raise ArgumentError.new("Server group requires at least one server")
      end
      @mutex = Mutex.new
      @stopped = false
      @closing = false
      @closed = false
      @shutdown_done = WaitGroup.new(1)
    end

    def bind : Array(Socket::IPAddress)
      @servers.map(&.bind)
    rescue ex
      close
      raise ex
    end

    def listen : Nil
      results = Channel(Exception?).new(@servers.size)
      @servers.each do |server|
        spawn do
          begin
            server.listen
            results.send(nil)
          rescue ex
            results.send(ex)
          end
        end
      end

      if error = results.receive
        raise error
      end
    end

    def stop : Nil
      @mutex.synchronize do
        return if @stopped

        @stopped = true
        @servers.each(&.stop)
      end
    end

    def shutdown : Nil
      stop
      owner, servers = claim_shutdown
      unless owner
        wait_until_closed unless servers.empty?
        return
      end

      begin
        servers.each(&.begin_shutdown)
        servers.each(&.wait_for_requests)
        drain_web_sockets(servers)
        servers.each(&.finish_shutdown)
      ensure
        mark_closed
      end
    end

    def close : Nil
      owner, servers = claim_shutdown
      unless owner
        wait_until_closed unless servers.empty?
        return
      end

      begin
        stop
        servers.each(&.close)
      ensure
        mark_closed
      end
    end

    private def drain_web_sockets(servers : Array(Server)) : Nil
      done = Channel(Nil).new(servers.size)
      servers.each do |server|
        spawn do
          server.drain_web_sockets
        ensure
          done.send(nil)
        end
      end
      servers.size.times { done.receive }
    end

    private def claim_shutdown : Tuple(Bool, Array(Server))
      @mutex.synchronize do
        if @closed
          {false, [] of Server}
        elsif @closing
          {false, @servers}
        else
          @closing = true
          {true, @servers}
        end
      end
    end

    private def mark_closed : Nil
      @mutex.synchronize { @closed = true }
      @shutdown_done.done
    end

    private def wait_until_closed : Nil
      @shutdown_done.wait
    end
  end
end
