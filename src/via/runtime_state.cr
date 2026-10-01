module Via
  record ConfigurationDiagnostic, source : String, message : String

  private class ProxyGeneration
    def initialize(routes : Array(Route), log : IO, debug : Bool, scheme : String)
      @proxy = Proxy.new(routes, log, debug, scheme)
      @mutex = Mutex.new
      @active_requests = 0
      @retired = false
      @closed = false
    end

    def acquire : Nil
      @mutex.synchronize do
        raise "cannot acquire a retired proxy generation" if @retired
        @active_requests += 1
      end
    end

    def call(context : HTTP::Server::Context) : Nil
      @proxy.call(context)
    end

    def release : Nil
      close = @mutex.synchronize do
        @active_requests -= 1
        close_if_retired_and_idle
      end
      @proxy.close if close
    end

    def retire : Nil
      close = @mutex.synchronize do
        @retired = true
        close_if_retired_and_idle
      end
      @proxy.close if close
    end

    private def close_if_retired_and_idle : Bool
      should_close = @retired && @active_requests == 0 && !@closed
      @closed = true if should_close

      should_close
    end
  end

  class RuntimeState
    @generation : ProxyGeneration?
    @diagnostic : ConfigurationDiagnostic?
    {% unless flag?(:without_openssl) %}
      @tls_context : OpenSSL::SSL::Context::Server?
    {% end %}

    def initialize(@log : IO = STDERR, @debug : Bool = false)
      @mutex = Mutex.new
      @generation = nil
      @diagnostic = nil
      {% unless flag?(:without_openssl) %}
        @tls_context = nil
      {% end %}
    end

    def apply(config : ValidatedConfig) : Nil
      tls_context = Tls.build(config.tls)
      scheme = config.tls ? "https" : "http"
      replacement = ProxyGeneration.new(config.routes, @log, @debug, scheme)
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
    end

    {% unless flag?(:without_openssl) %}
      def tls_context : OpenSSL::SSL::Context::Server
        @mutex.synchronize do
          @tls_context ||
            raise ConfigurationError.new("TLS context is not available")
        end
      end
    {% end %}

    def reject(source : String, error : Exception) : Nil
      @log.puts "configuration_error source=#{source.inspect} message=#{error.message.inspect}"
      return unless @debug

      @mutex.synchronize do
        @diagnostic = ConfigurationDiagnostic.new(source, error.message || error.class.name)
      end
    end

    def call(context : HTTP::Server::Context) : Nil
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
        request_id = RequestId.generate
        ErrorPages.render(
          context.response,
          HTTP::Status::SERVICE_UNAVAILABLE,
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
      context : HTTP::Server::Context,
      diagnostic : ConfigurationDiagnostic,
    ) : Nil
      request_id = RequestId.generate
      content = String.build do |body|
        body << "via debug\n\n"
        body << "Configuration error\n\n"
        body << diagnostic.source << '\n'
        body << diagnostic.message << "\n\n"
        body << "Via is watching for a valid configuration.\n\n"
        body << "Request ID: " << request_id << '\n'
      end

      response = context.response
      response.status = :service_unavailable
      response.content_type = "text/plain; charset=utf-8"
      response.content_length = content.bytesize
      response.headers["X-Request-ID"] = request_id
      response << content unless context.request.method == "HEAD"
    end
  end
end
