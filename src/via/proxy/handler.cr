module Via::Proxy
  class Handler
    def initialize(
      routes : Enumerable(Routing::Route),
      @log : IO = STDERR,
      @debug : Bool = false,
      @scheme : String = "http",
    )
      route_list = routes.to_a
      @router = Routing::Router.new(route_list)
      @clients = {} of String => Pool
      route_list.each do |route|
        if upstream = route.upstream
          @clients[upstream.to_s] ||= Pool.new(upstream)
        end
      end
    end

    def close : Nil
      @clients.each_value(&.close)
    end

    def call(context : ::HTTP::Server::Context) : Nil
      request = context.request
      response = context.response
      downstream_started = false
      request_id = Via::HTTP::RequestId.generate
      response.headers["X-Request-ID"] = request_id

      unless Via::HTTP::ForwardedHeaders.valid_host?(request)
        log_error(request_id, :bad_request, request)
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::BAD_REQUEST,
          request_id,
          head: request.method == "HEAD"
        )
        return
      end

      route = @router.match(request.headers["Host"]?, request.path)

      unless route
        log_error(request_id, :not_found, request)
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::NOT_FOUND,
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
        Static::Files.call(context, route.path, static_target, request_id)
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
        headers = Via::HTTP::ForwardedHeaders.request(request, upstream, request_id, @scheme)
        client.exec(request.method, request.resource, headers, request.body) do |upstream_response|
          response.status = upstream_response.status
          if @debug
            @log.puts(
              "request_id=#{request_id} upstream_status=#{upstream_response.status_code}"
            )
          end
          Via::HTTP::ForwardedHeaders.copy_response(upstream_response.headers, response.headers)
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
      request_id ||= Via::HTTP::RequestId.generate
      if downstream_started
        @log.puts "request_id=#{request_id} error=proxy_stream message=#{ex.message.inspect}"
      else
        @log.puts "request_id=#{request_id} error=bad_gateway message=#{ex.message.inspect}"
        Via::HTTP::ErrorPages.render(
          context.response,
          ::HTTP::Status::BAD_GATEWAY,
          request_id,
          head: context.request.method == "HEAD"
        )
      end
    end

    private def log_error(request_id : String, error : Symbol, request : ::HTTP::Request) : Nil
      @log.puts(
        "request_id=#{request_id} error=#{error} " \
        "method=#{request.method.inspect} path=#{request.resource.inspect}"
      )
    end
  end
end
