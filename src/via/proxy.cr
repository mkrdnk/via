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

    NOT_FOUND_BODY = <<-TEXT
      via

      404
      Not Found

      No route matched this request.
      TEXT

    def initialize(routes : Enumerable(Route), @log : IO = STDERR)
      route_list = routes.to_a
      @router = Router.new(route_list)
      @clients = {} of String => ClientPool
      route_list.each do |route|
        @clients[route.upstream.to_s] ||= ClientPool.new(route.upstream)
      end
    end

    def call(context : HTTP::Server::Context) : Nil
      request = context.request
      response = context.response
      downstream_started = false
      route = @router.match(request.headers["Host"]?, request.path)

      unless route
        not_found(response)
        return
      end

      @clients[route.upstream.to_s].with do |client|
        headers = request_headers(request, route.upstream)
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

    private def request_headers(request : HTTP::Request, upstream : URI) : HTTP::Headers
      headers = forwarded_headers(request.headers)
      original_host = request.headers["Host"]?

      headers["Host"] = upstream_authority(upstream)
      if original_host
        headers["X-Forwarded-Host"] = original_host
      else
        headers.delete("X-Forwarded-Host")
      end
      headers["X-Forwarded-Proto"] = "http"

      if address = request.remote_address
        if address.is_a?(Socket::IPAddress)
          client_ip = address.address
          if forwarded_for = headers["X-Forwarded-For"]?.try(&.presence)
            headers["X-Forwarded-For"] = "#{forwarded_for}, #{client_ip}"
          else
            headers["X-Forwarded-For"] = client_ip
          end
        end
      end

      headers
    end

    private def upstream_authority(upstream : URI) : String
      hostname = upstream.hostname.not_nil!
      hostname = "[#{hostname}]" if hostname.includes?(':')
      port = upstream.port
      default_port = upstream.scheme == "https" ? 443 : 80

      port && port != default_port ? "#{hostname}:#{port}" : hostname
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

    private def not_found(response : HTTP::Server::Response) : Nil
      response.status = :not_found
      response.content_type = "text/plain; charset=utf-8"
      response.content_length = NOT_FOUND_BODY.bytesize
      response << NOT_FOUND_BODY
    end
  end
end
