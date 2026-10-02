module Via
  class ServerGroup
    def initialize(@servers : Array(Server))
      if @servers.empty?
        raise ArgumentError.new("Server group requires at least one server")
      end
      @mutex = Mutex.new
      @closed = false
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

    def close : Nil
      servers = @mutex.synchronize do
        next [] of Server if @closed

        @closed = true
        @servers
      end
      servers.each(&.close)
    end
  end
end
