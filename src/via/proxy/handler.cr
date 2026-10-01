module Via::Proxy
  class Handler
    def initialize(
      routes : Enumerable(Routing::Route),
      @logger : Logging::Logger,
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
      response_bytes = 0_i64
      target = "none"
      route_path = nil.as(String?)
      upstream_name = nil.as(String?)
      failure = nil.as(String?)
      started_at = Time.instant
      request_id = Via::HTTP::RequestId.generate
      response.headers["X-Request-ID"] = request_id
      @logger.debug(
        "request.started",
        request_id: request_id,
        client: client_address(request),
        method: request.method,
        host: request.headers["Host"]?,
        path: request.path
      )

      unless Via::HTTP::ForwardedHeaders.valid_host?(request)
        failure = "invalid_host"
        @logger.warn(
          "request.rejected",
          request_id: request_id,
          reason: failure,
          method: request.method,
          path: request.path
        )
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
        failure = "route_not_found"
        @logger.warn(
          "routing.miss",
          request_id: request_id,
          host: request.headers["Host"]?,
          path: request.path
        )
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::NOT_FOUND,
          request_id,
          head: request.method == "HEAD"
        )
        return
      end

      route_path = route.path
      if static_target = route.static_target
        target = "static"
        @logger.debug(
          "routing.selected",
          request_id: request_id,
          target: target,
          route_host: route.host,
          route_path: route.path,
          static_root: static_target.root
        )
        Static::Files.call(context, route.path, static_target, request_id)
        return
      end

      target = "proxy"
      upstream = route.upstream.not_nil!
      upstream_name = upstream.to_s
      @logger.debug(
        "routing.selected",
        request_id: request_id,
        target: target,
        route_host: route.host,
        route_path: route.path,
        upstream: upstream_name
      )

      @clients[upstream.to_s].with do |client|
        headers = Via::HTTP::ForwardedHeaders.request(request, upstream, request_id, @scheme)
        client.exec(request.method, request.resource, headers, request.body) do |upstream_response|
          response.status = upstream_response.status
          @logger.debug(
            "upstream.response",
            request_id: request_id,
            upstream: upstream_name,
            status: upstream_response.status_code
          )
          Via::HTTP::ForwardedHeaders.copy_response(upstream_response.headers, response.headers)
          response.headers["X-Request-ID"] = request_id

          if body = upstream_response.body_io?
            buffer = Bytes.new(16 * 1024)
            count = body.read(buffer)

            if count > 0
              downstream_started = true
              response_bytes += count
              response.write(buffer[0, count])
              response_bytes += IO.copy(body, response)
            end
          end
        end
      end
    rescue ex : IO::Error | Socket::Error
      request_id ||= Via::HTTP::RequestId.generate
      if downstream_started
        failure = "stream_failed"
        @logger.error(
          "stream.failed",
          request_id: request_id,
          upstream: upstream_name,
          message: ex.message
        )
      else
        failure = "upstream_failed"
        @logger.error(
          "upstream.failed",
          request_id: request_id,
          upstream: upstream_name,
          message: ex.message
        )
        Via::HTTP::ErrorPages.render(
          context.response,
          ::HTTP::Status::BAD_GATEWAY,
          request_id,
          head: context.request.method == "HEAD"
        )
      end
    ensure
      if request_id
        response_bytes = context.response.content_length || response_bytes
        @logger.info(
          "request.completed",
          request_id: request_id,
          client: client_address(context.request),
          method: context.request.method,
          host: context.request.headers["Host"]?,
          path: context.request.path,
          target: target,
          route_path: route_path,
          upstream: upstream_name,
          status: context.response.status_code,
          request_bytes: context.request.content_length,
          response_bytes: response_bytes,
          duration_ms: (Time.instant - started_at.not_nil!).total_milliseconds.round(3),
          failure: failure
        )
      end
    end

    private def client_address(request : ::HTTP::Request) : String?
      case address = request.remote_address
      when Socket::IPAddress
        address.address
      when Socket::UNIXAddress
        address.path
      end
    end
  end
end
