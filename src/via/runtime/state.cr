module Via::Runtime
  record Diagnostic, source : String, message : String

  class State
    @generation : Generation?
    @diagnostic : Diagnostic?
    {% unless flag?(:without_openssl) %}
      @tls_context : OpenSSL::SSL::Context::Server?
    {% end %}

    def initialize(log : IO = STDERR, @debug : Bool = false)
      @mutex = Mutex.new
      @logger = Logging::Logger.new(log, @debug)
      @generation = nil
      @diagnostic = nil
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
      tls_context = TLS::ContextBuilder.build(config.tls)
      scheme = config.tls ? "https" : "http"
      replacement = Generation.new(config.routes, @logger, scheme)
      previous = @mutex.synchronize do
        old = @generation
        @generation = replacement
        @diagnostic = nil
        {% unless flag?(:without_openssl) %}
          @tls_context = tls_context
        {% end %}
        old
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
      keeping_previous = @mutex.synchronize do
        previous = !@generation.nil?
        if @debug
          @diagnostic = Diagnostic.new(source, error.message || error.class.name)
        end
        previous
      end
      @logger.error(
        "config.rejected",
        source: source,
        message: error.message,
        keeping_previous: keeping_previous,
        diagnostic: @debug
      )
    end

    def call(context : ::HTTP::Server::Context) : Nil
      generation = nil
      diagnostic = nil

      @mutex.synchronize do
        diagnostic = @diagnostic
        unless diagnostic
          generation = @generation
          generation.try(&.acquire)
        end
      end

      if current_diagnostic = diagnostic
        render_diagnostic(context, current_diagnostic)
      elsif current_generation = generation
        begin
          current_generation.call(context)
        ensure
          current_generation.release
        end
      else
        request_id = Via::HTTP::RequestId.generate
        Via::HTTP::ErrorPages.render(
          context.response,
          ::HTTP::Status::SERVICE_UNAVAILABLE,
          request_id,
          head: context.request.method == "HEAD"
        )
      end
    end

    def close : Nil
      previous = @mutex.synchronize do
        old = @generation
        @generation = nil
        @diagnostic = nil
        {% unless flag?(:without_openssl) %}
          @tls_context = nil
        {% end %}
        old
      end
      previous.try(&.retire)
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
  end
end
