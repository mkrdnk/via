module Via::Runtime
  record Diagnostic, source : String, message : String

  class State
    @generation : Generation?
    @diagnostic : Diagnostic?
    {% unless flag?(:without_openssl) %}
      @tls_context : OpenSSL::SSL::Context::Server?
    {% end %}

    def initialize(
      log : IO = STDERR,
      debug : Bool = false,
      @log_level_override : Logging::Level? = nil,
      configured_debug : Bool = false,
    )
      @mutex = Mutex.new
      @debug_override = debug
      @debug = @debug_override || configured_debug
      @logger = Logging::Logger.new(log, @debug)
      @generation = nil
      @diagnostic = nil
      @web_sockets = WebSocketRegistry.new
      @websocket_shutdown_timeout = Configuration::DEFAULT_WEBSOCKET_SHUTDOWN_TIMEOUT
      @accepting_requests = true
      @active_requests = 0
      @requests_drained = Channel(Nil).new(1)
      @closed = false
      {% unless flag?(:without_openssl) %}
        @tls_context = nil
      {% end %}
    end

    def apply(
      config : Configuration::Validated,
      *,
      source : String? = nil,
      reloaded : Bool = false,
    ) : Nil
      @logger.config_file = source if source
      tls_context = TLS::ContextBuilder.build(config.tls)
      scheme = config.tls ? "https" : "http"
      replacement = Generation.new(config.routes, @logger, scheme, @web_sockets)
      debug = @debug_override || config.debug
      level = @log_level_override ||
              (debug ? Logging::Level::Debug : config.log_level || Logging::Level::Info)
      begin
        @logger.configure(config.log_file, level)
      rescue ex
        replacement.retire
        raise ex
      end
      previous = nil.as(Generation?)
      installed = false
      @mutex.synchronize do
        unless @closed
          previous = @generation
          @generation = replacement
          @diagnostic = nil
          @debug = debug
          @websocket_shutdown_timeout = config.websocket_shutdown_timeout
          {% unless flag?(:without_openssl) %}
            @tls_context = tls_context
          {% end %}
          installed = true
        end
      end

      unless installed
        replacement.retire
        @logger.close
        return
      end

      previous.try(&.retire)
      @logger.info(
        reloaded ? "config.reloaded" : "config.applied",
        source: source,
        routes: config.routes.size,
        tls: !config.tls.nil?
      )
    end

    {% unless flag?(:without_openssl) %}
      def tls_context : OpenSSL::SSL::Context::Server
        @mutex.synchronize do
          @tls_context ||
            raise Configuration::Error.new("TLS context is not available")
        end
      end
    {% end %}

    def reject(source : String, error : Exception) : Nil
      @logger.config_file = source
      keeping_previous, diagnostic_enabled = @mutex.synchronize do
        previous = !@generation.nil?
        current_debug = @debug
        if current_debug
          @diagnostic = Diagnostic.new(source, error.message || error.class.name)
        end
        {previous, current_debug}
      end
      @logger.error(
        "config.rejected",
        source: source,
        message: error.message,
        keeping_previous: keeping_previous,
        diagnostic: diagnostic_enabled
      )
    end

    def call(context : ::HTTP::Server::Context) : Nil
      Via::HTTP::ServerHeader.apply(context.response.headers)
      generation = nil
      diagnostic = nil
      accepted = false
      completion = nil.as(RequestCompletion?)

      @mutex.synchronize do
        if @accepting_requests
          @active_requests += 1
          accepted = true
          diagnostic = @diagnostic
          unless diagnostic
            generation = @generation
            generation.try(&.acquire)
          end
        end
      end

      if accepted
        completion = RequestCompletion.new { release_request }
        context.response.output = completion.wrap(context.response.output)
      end

      if !accepted
        context.response.headers["Connection"] = "close"
        render_unavailable(context)
      elsif current_diagnostic = diagnostic
        render_diagnostic(context, current_diagnostic)
      elsif current_generation = generation
        begin
          current_generation.call(context)
        ensure
          current_generation.release
        end
      else
        render_unavailable(context)
      end
    rescue ex : ::HTTP::Server::ClientError
      raise ex
    rescue ex
      begin
        @logger.error(
          "request.unhandled",
          method: context.request.method,
          path: context.request.path,
          message: ex.message
        )
      rescue
        # A logging backend failure must not prevent the tracked response from
        # being finalized.
      end
      finalize_failed_request(context)
    ensure
      completion.try(&.handler_finished)
    end

    def begin_shutdown : Nil
      notify = @mutex.synchronize do
        @accepting_requests = false
        @active_requests == 0
      end
      notify_requests_drained if notify
    end

    def wait_for_requests : Nil
      begin_shutdown
      @requests_drained.receive
    end

    def drain_web_sockets : Nil
      timeout = @mutex.synchronize { @websocket_shutdown_timeout }
      @web_sockets.drain(timeout)
    end

    def close : Nil
      previous = @mutex.synchronize do
        return if @closed

        @closed = true
        old = @generation
        @accepting_requests = false
        @generation = nil
        @diagnostic = nil
        {% unless flag?(:without_openssl) %}
          @tls_context = nil
        {% end %}
        old
      end
      @web_sockets.close
      previous.try(&.retire)
      @logger.close
    end

    private def render_diagnostic(
      context : ::HTTP::Server::Context,
      diagnostic : Diagnostic,
    ) : Nil
      request_id = Via::HTTP::RequestId.generate
      content = Via::HTTP::ErrorPages.diagnostic(
        diagnostic.source,
        diagnostic.message,
        request_id
      )

      response = context.response
      response.status = :service_unavailable
      response.content_type = "text/html; charset=utf-8"
      response.content_length = content.bytesize
      response.headers["X-Request-ID"] = request_id
      response << content unless context.request.method == "HEAD"
    end

    private def render_unavailable(context : ::HTTP::Server::Context) : Nil
      request_id = Via::HTTP::RequestId.generate
      Via::HTTP::ErrorPages.render(
        context.response,
        ::HTTP::Status::SERVICE_UNAVAILABLE,
        request_id,
        head: context.request.method == "HEAD"
      )
    end

    private def finalize_failed_request(context : ::HTTP::Server::Context) : Nil
      response = context.response
      return if response.closed?

      begin
        request_id = Via::HTTP::RequestId.generate
        Via::HTTP::ErrorPages.render(
          response,
          ::HTTP::Status::INTERNAL_SERVER_ERROR,
          request_id,
          head: context.request.method == "HEAD"
        )
      rescue IO::Error
        # Headers may already have been sent. Preserve that response and close
        # its tracked output instead of resetting it.
      end
      response.close unless response.closed?
    end

    private def release_request : Nil
      notify = @mutex.synchronize do
        @active_requests -= 1
        !@accepting_requests && @active_requests == 0
      end
      notify_requests_drained if notify
    end

    private def notify_requests_drained : Nil
      select
      when @requests_drained.send(nil)
      else
      end
    end
  end
end
