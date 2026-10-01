module Via
  # Keeps a bounded number of idle clients while allowing concurrency to grow
  # with demand. A checked-out HTTP::Client is owned by one fiber only.
  class ClientPool
    class ClosedError < Exception
    end

    def initialize(@upstream : URI, max_idle = 32)
      raise ArgumentError.new("max_idle must be positive") unless max_idle > 0

      @available = Channel(HTTP::Client).new(max_idle)
      @mutex = Mutex.new
      @closed = false
    end

    def with(& : HTTP::Client ->)
      client = checkout
      reusable = false

      begin
        result = yield client
        reusable = true
        result
      ensure
        reusable ? checkin(client) : client.close
      end
    end

    def close : Nil
      @mutex.synchronize do
        return if @closed

        @closed = true
        loop do
          select
          when client = @available.receive
            client.close
          else
            break
          end
        end
      end
    end

    private def checkout : HTTP::Client
      @mutex.synchronize do
        raise ClosedError.new("client pool is closed") if @closed

        select
        when client = @available.receive
          client
        else
          client = HTTP::Client.new(@upstream)
          client.compress = false
          client
        end
      end
    end

    private def checkin(client : HTTP::Client) : Nil
      @mutex.synchronize do
        if @closed
          client.close
        else
          select
          when @available.send(client)
          else
            client.close
          end
        end
      end
    end
  end
end
