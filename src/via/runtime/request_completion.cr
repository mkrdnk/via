module Via::Runtime
  # Releases a request only after both its handler and its finalized response
  # output have completed. HTTP::Server closes the response after the handler
  # returns, so handler-level tracking alone can return from shutdown too early.
  class RequestCompletion
    class Output < IO
      def initialize(
        @output : IO,
        @completion : RequestCompletion,
      )
        @closed = false
      end

      def read(slice : Bytes) : Int32
        @output.read(slice)
      end

      def write(slice : Bytes) : Nil
        @output.write(slice)
      end

      def flush : Nil
        @output.flush
      end

      def close : Nil
        return if @closed

        begin
          @output.close
          # Response::Output may write only headers while closing. Flush its
          # underlying connection before declaring the request complete.
          @output.flush
        rescue ::HTTP::Server::ClientError | IO::Error
          # A disconnected downstream is complete from the server's
          # perspective and must not keep shutdown blocked.
        ensure
          @closed = true
          @completion.output_finished
        end
      end

      def closed? : Bool
        @closed
      end
    end

    def initialize(&@on_complete : ->)
      @mutex = Mutex.new
      @handler_finished = false
      @output_finished = false
      @completed = false
    end

    def wrap(output : IO) : IO
      Output.new(output, self)
    end

    def handler_finished : Nil
      complete(handler: true)
    end

    def output_finished : Nil
      complete(output: true)
    end

    private def complete(
      *,
      handler : Bool = false,
      output : Bool = false,
    ) : Nil
      notify = @mutex.synchronize do
        @handler_finished = true if handler
        @output_finished = true if output
        ready = @handler_finished && @output_finished && !@completed
        @completed = true if ready
        ready
      end
      @on_complete.call if notify
    end
  end
end
