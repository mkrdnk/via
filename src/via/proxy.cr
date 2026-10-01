module Via
  class Proxy
    HOP_BY_HOP_HEADERS = {
      "Connection",
      "Keep-Alive",
      "Proxy-Authenticate",
      "Proxy-Authorization",
      "TE",
      "Trailer",
      "Transfer-Encoding",
      "Upgrade",
    }

    BAD_GATEWAY_BODY = <<-TEXT
      via

      502
      Bad Gateway

      The upstream server could not be reached.
      TEXT

    def initialize(upstream : URI, @log : IO = STDERR)
      @clients = ClientPool.new(upstream)
    end

    def call(context : HTTP::Server::Context) : Nil
      request = context.request
      response = context.response
      downstream_started = false

      @clients.with do |client|
        headers = forwarded_headers(request.headers)
        client.exec(request.method, request.resource, headers, request.body) do |upstream_response|
          response.status = upstream_response.status
          copy_headers(upstream_response.headers, response.headers)

          if body = upstream_response.body_io?
            buffer = Bytes.new(16 * 1024)
            count = body.read(buffer)

            if count > 0
              downstream_started = true
              response.write(buffer[0, count])
              IO.copy(body, response)
            end
          end
        end
      end
    rescue ex : IO::Error | Socket::Error
      if downstream_started
        @log.puts "Proxy stream error: #{ex.message}"
      else
        bad_gateway(context.response, ex)
      end
    end

    def self.forwarded_headers(source : HTTP::Headers) : HTTP::Headers
      headers = source.dup

      if connection = headers["Connection"]?
        connection.split(',').each do |name|
          headers.delete(name.strip)
        end
      end

      HOP_BY_HOP_HEADERS.each { |name| headers.delete(name) }
      headers
    end

    private def forwarded_headers(source : HTTP::Headers) : HTTP::Headers
      self.class.forwarded_headers(source)
    end

    private def copy_headers(source : HTTP::Headers, destination : HTTP::Headers) : Nil
      forwarded_headers(source).each do |name, values|
        values.each { |value| destination.add(name, value) }
      end
    end

    private def bad_gateway(response : HTTP::Server::Response, error : Exception) : Nil
      @log.puts "Upstream error: #{error.message}"
      response.status = :bad_gateway
      response.content_type = "text/plain; charset=utf-8"
      response.content_length = BAD_GATEWAY_BODY.bytesize
      response << BAD_GATEWAY_BODY
    end
  end
end
