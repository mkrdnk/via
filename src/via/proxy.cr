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

    def initialize(
      routes : Enumerable(Route),
      @log : IO = STDERR,
      @debug : Bool = false,
      @scheme : String = "http",
    )
      route_list = routes.to_a
      @router = Router.new(route_list)
      @clients = {} of String => ClientPool
      route_list.each do |route|
        if upstream = route.upstream
          @clients[upstream.to_s] ||= ClientPool.new(upstream)
        end
      end
    end

    def close : Nil
      @clients.each_value(&.close)
    end

    def call(context : HTTP::Server::Context) : Nil
      request = context.request
      response = context.response
      downstream_started = false
      request_id = RequestId.generate
      response.headers["X-Request-ID"] = request_id

      unless valid_host?(request)
        log_error(request_id, :bad_request, request)
        ErrorPages.render(
          response,
          HTTP::Status::BAD_REQUEST,
          request_id,
          head: request.method == "HEAD"
        )
        return
      end

      route = @router.match(request.headers["Host"]?, request.path)

      unless route
        log_error(request_id, :not_found, request)
        ErrorPages.render(
          response,
          HTTP::Status::NOT_FOUND,
          request_id,
          head: request.method == "HEAD"
        )
        return
      end

      if static_target = route.static_target
        if @debug
          @log.puts(
            "request_id=#{request_id} method=#{request.method.inspect} " \
            "path=#{request.resource.inspect} static_root=#{static_target.root.inspect}"
          )
        end
        StaticFiles.call(context, route.path, static_target, request_id)
        return
      end

      upstream = route.upstream.not_nil!
      if @debug
        @log.puts(
          "request_id=#{request_id} method=#{request.method.inspect} " \
          "path=#{request.resource.inspect} upstream=#{upstream}"
        )
      end

      @clients[upstream.to_s].with do |client|
        headers = request_headers(request, upstream, request_id)
        client.exec(request.method, request.resource, headers, request.body) do |upstream_response|
          response.status = upstream_response.status
          if @debug
            @log.puts(
              "request_id=#{request_id} upstream_status=#{upstream_response.status_code}"
            )
          end
          copy_headers(upstream_response.headers, response.headers)
          response.headers["X-Request-ID"] = request_id

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
      request_id ||= RequestId.generate
      if downstream_started
        @log.puts "request_id=#{request_id} error=proxy_stream message=#{ex.message.inspect}"
      else
        @log.puts "request_id=#{request_id} error=bad_gateway message=#{ex.message.inspect}"
        ErrorPages.render(
          context.response,
          HTTP::Status::BAD_GATEWAY,
          request_id,
          head: context.request.method == "HEAD"
        )
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

    private def request_headers(
      request : HTTP::Request,
      upstream : URI,
      request_id : String,
    ) : HTTP::Headers
      headers = forwarded_headers(request.headers)
      original_host = request.headers["Host"]?

      headers["Host"] = upstream_authority(upstream)
      headers["X-Request-ID"] = request_id
      if original_host
        headers["X-Forwarded-Host"] = original_host
      else
        headers.delete("X-Forwarded-Host")
      end
      headers["X-Forwarded-Proto"] = @scheme

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

    private def valid_host?(request : HTTP::Request) : Bool
      host = request.headers["Host"]?
      return false if request.version == "HTTP/1.1" && host.nil?
      return true unless host

      !Router.normalize_request_host(host).nil?
    end

    private def copy_headers(source : HTTP::Headers, destination : HTTP::Headers) : Nil
      forwarded_headers(source).each do |name, values|
        values.each { |value| destination.add(name, value) }
      end
    end

    private def log_error(request_id : String, error : Symbol, request : HTTP::Request) : Nil
      @log.puts(
        "request_id=#{request_id} error=#{error} " \
        "method=#{request.method.inspect} path=#{request.resource.inspect}"
      )
    end
  end
end
