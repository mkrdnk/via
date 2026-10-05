module Via::Proxy
  class Handler
    {% if flag?(:without_openssl) %}
      alias TransportError = IO::Error | Socket::Error
    {% else %}
      alias TransportError = IO::Error | Socket::Error | OpenSSL::Error
    {% end %}

    private class TransferState
      property downstream_started = false
      property response_bytes = 0_i64
    end

    private record PoolKey,
      upstream : URI,
      timeouts : Routing::Timeouts

    def initialize(
      routes : Enumerable(Routing::Route),
      @logger : Logging::Logger,
      @scheme : String = "http",
      @web_sockets : Runtime::WebSocketRegistry = Runtime::WebSocketRegistry.new,
    )
      route_list = routes.to_a
      @router = Routing::Router.new(route_list)
      @clients = {} of PoolKey => Pool
      route_list.each do |route|
        if upstream = route.upstream
          key = PoolKey.new(upstream, route.timeouts)
          @clients[key] ||= Pool.new(upstream, timeouts: route.timeouts)
        end
      end
    end

    def close : Nil
      @clients.each_value(&.close)
    end

    def call(context : ::HTTP::Server::Context) : Nil
      transfer = TransferState.new
      request = context.request
      response = context.response
      target = "none"
      route_path = nil.as(String?)
      upstream_name = nil.as(String?)
      failure = nil.as(String?)
      started_at = Time.instant
      request_id = nil.as(String?)
      id = Via::HTTP::RequestId.generate
      request_id = id
      response.headers["X-Request-ID"] = id
      @logger.debug(
        "request.started",
        request_id: id,
        client: client_address(request),
        method: request.method,
        host: request.headers["Host"]?,
        path: request.path
      )

      unless Via::HTTP::ForwardedHeaders.valid_host?(request)
        failure = "invalid_host"
        @logger.warn(
          "request.rejected",
          request_id: id,
          reason: failure,
          method: request.method,
          path: request.path
        )
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::BAD_REQUEST,
          id,
          head: request.method == "HEAD"
        )
        return
      end

      route = @router.match(request.headers["Host"]?, request.path)

      unless route
        failure = "route_not_found"
        @logger.warn(
          "routing.miss",
          request_id: id,
          host: request.headers["Host"]?,
          path: request.path
        )
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::NOT_FOUND,
          id,
          head: request.method == "HEAD"
        )
        return
      end

      route_path = route.path
      if response_status = route.response_status
        target = "response"
        @logger.debug(
          "routing.selected",
          request_id: id,
          target: target,
          route_host: route.host,
          route_path: route.path,
          status: response_status
        )
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status.new(response_status),
          id,
          head: request.method == "HEAD"
        )
        return
      end

      if static_target = route.static_target
        target = "static"
        @logger.debug(
          "routing.selected",
          request_id: id,
          target: target,
          route_host: route.host,
          route_path: route.path,
          static_root: static_target.root
        )
        Static::Files.call(context, route.path, static_target, id)
        return
      end

      target = "proxy"
      upstream = route.upstream.not_nil!
      upstream_name = upstream.to_s
      @logger.debug(
        "routing.selected",
        request_id: id,
        target: target,
        route_host: route.host,
        route_path: route.path,
        upstream: upstream_name
      )

      if WebSocketTunnel.request?(request)
        upstream_io = WebSocketTunnel.connect(upstream, route.timeouts)
        upgraded = false

        begin
          headers = WebSocketTunnel.request_headers(
            request,
            upstream,
            id,
            @scheme
          )
          WebSocketTunnel.send_request(upstream_io, request, headers)
          WebSocketTunnel.read_response(upstream_io) do |upstream_response|
            response.status = upstream_response.status
            @logger.debug(
              "upstream.response",
              request_id: id,
              upstream: upstream_name,
              status: upstream_response.status_code
            )

            if WebSocketTunnel.response?(request, upstream_response)
              WebSocketTunnel.copy_response(upstream_response.headers, response.headers)
              response.headers["X-Request-ID"] = id
              WebSocketTunnel.upgrade(
                response,
                upstream_io,
                @logger,
                id,
                upstream_name,
                @web_sockets
              )
              upgraded = true
              transfer.downstream_started = true
            elsif upstream_response.status.switching_protocols?
              raise Socket::Error.new("Invalid WebSocket upgrade response")
            else
              copy_response(upstream_response, response, id, transfer)
            end
          end
        ensure
          upstream_io.close unless upgraded
        end
      else
        key = PoolKey.new(upstream, route.timeouts)
        @clients[key].with do |client|
          headers = Via::HTTP::ForwardedHeaders.request(request, upstream, id, @scheme)
          client.exec(request.method, request.resource, headers, request.body) do |upstream_response|
            response.status = upstream_response.status
            @logger.debug(
              "upstream.response",
              request_id: id,
              upstream: upstream_name,
              status: upstream_response.status_code
            )
            copy_response(upstream_response, response, id, transfer)
          end
        end
      end
    rescue ex : TransportError
      request_id ||= Via::HTTP::RequestId.generate
      timed_out = ex.is_a?(IO::TimeoutError)
      if transfer && transfer.downstream_started
        failure = timed_out ? "stream_timeout" : "stream_failed"
        @logger.error(
          "stream.failed",
          request_id: request_id,
          upstream: upstream_name,
          message: ex.message
        )
      else
        failure = timed_out ? "upstream_timeout" : "upstream_failed"
        @logger.error(
          "upstream.failed",
          request_id: request_id,
          upstream: upstream_name,
          message: ex.message
        )
        Via::HTTP::ErrorPages.render(
          context.response,
          timed_out ? ::HTTP::Status::GATEWAY_TIMEOUT : ::HTTP::Status::BAD_GATEWAY,
          request_id,
          head: context.request.method == "HEAD"
        )
      end
    ensure
      if request_id
        response_bytes = context.response.content_length ||
                         transfer.try(&.response_bytes) ||
                         0_i64
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

    private def copy_response(
      upstream : ::HTTP::Client::Response,
      downstream : ::HTTP::Server::Response,
      request_id : String,
      transfer : TransferState,
    ) : Nil
      Via::HTTP::ForwardedHeaders.copy_response(upstream.headers, downstream.headers)
      downstream.headers["X-Request-ID"] = request_id

      if body = upstream.body_io?
        buffer = Bytes.new(16 * 1024)
        while (count = body.read(buffer)) > 0
          transfer.downstream_started = true
          transfer.response_bytes += count
          downstream.write(buffer[0, count])
        end
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
