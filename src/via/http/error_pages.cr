require "html"

module Via::HTTP
  module ErrorPages
    record Definition, title : String, message : String

    DEFINITIONS = {
      ::HTTP::Status::BAD_REQUEST => Definition.new(
        "Bad Request",
        "The request could not be understood."
      ),
      ::HTTP::Status::FORBIDDEN => Definition.new(
        "Forbidden",
        "Access to this resource is forbidden."
      ),
      ::HTTP::Status::NOT_FOUND => Definition.new(
        "Not Found",
        "The requested resource was not found."
      ),
      ::HTTP::Status::METHOD_NOT_ALLOWED => Definition.new(
        "Method Not Allowed",
        "This resource does not support the request method."
      ),
      ::HTTP::Status::RANGE_NOT_SATISFIABLE => Definition.new(
        "Range Not Satisfiable",
        "The requested byte range cannot be served."
      ),
      ::HTTP::Status::BAD_GATEWAY => Definition.new(
        "Bad Gateway",
        "The upstream server could not be reached."
      ),
      ::HTTP::Status::SERVICE_UNAVAILABLE => Definition.new(
        "Service Unavailable",
        "The service is temporarily unavailable."
      ),
      ::HTTP::Status::GATEWAY_TIMEOUT => Definition.new(
        "Gateway Timeout",
        "The upstream server did not respond in time."
      ),
    }

    def self.body(status : ::HTTP::Status, request_id : String) : String
      definition = DEFINITIONS[status]? || default_definition(status)

      document(status.code, definition.title, definition.message, request_id)
    end

    def self.diagnostic(source : String, message : String, request_id : String) : String
      details = String.build do |html|
        html << %(<dl><dt>Configuration</dt><dd>)
        ::HTML.escape(source, html)
        html << %(</dd><dt>Error</dt><dd>)
        ::HTML.escape(message, html)
        html << "</dd></dl>"
      end

      document(
        ::HTTP::Status::SERVICE_UNAVAILABLE.code,
        "Configuration error",
        "Via is watching for a valid configuration.",
        request_id,
        details
      )
    end

    def self.render(
      response : ::HTTP::Server::Response,
      status : ::HTTP::Status,
      request_id : String,
      *,
      head : Bool = false,
      additional_headers : ::HTTP::Headers? = nil,
    ) : Nil
      content = body(status, request_id)
      content_forbidden = content_forbidden?(status)
      response.headers.clear
      response.status = status
      unless content_forbidden
        response.content_type = "text/html; charset=utf-8"
        response.content_length = content.bytesize
      end
      response.headers["X-Request-ID"] = request_id
      additional_headers.try do |headers|
        headers.each do |name, values|
          values.each { |value| response.headers.add(name, value) }
        end
      end
      response << content unless head || content_forbidden
    end

    private def self.default_definition(status : ::HTTP::Status) : Definition
      title = status.description || "HTTP Status"
      message = if status.client_error?
                  "The request could not be completed."
                elsif status.server_error?
                  "The server could not complete the request."
                elsif status.redirection?
                  "The request resulted in a redirect response."
                else
                  "The request completed with this status."
                end

      Definition.new(title, message)
    end

    private def self.content_forbidden?(status : ::HTTP::Status) : Bool
      status.in?(
        ::HTTP::Status::NO_CONTENT,
        ::HTTP::Status::RESET_CONTENT,
        ::HTTP::Status::NOT_MODIFIED
      )
    end

    private def self.document(
      code : Int,
      title : String,
      message : String,
      request_id : String,
      details : String? = nil,
    ) : String
      String.build do |html|
        html << "<!doctype html><html lang=\"en\"><head>"
        html << "<meta charset=\"utf-8\">"
        html << %(<meta name="viewport" content="width=device-width,initial-scale=1">)
        html << %(<link rel="icon" href="#{Favicon::DATA_URI}" type="image/svg+xml">)
        html << "<title>#{code} "
        ::HTML.escape(title, html)
        html << " — Via</title>"
        html << "<style>"
        html << "html{color-scheme:light dark}body{max-width:42rem;margin:12vh auto;"
        html << "padding:0 1.5rem;font:16px/1.5 system-ui,sans-serif}"
        html << "header{font-weight:700;letter-spacing:.08em;text-transform:lowercase}"
        html << "h1{font-size:clamp(2rem,8vw,4rem);line-height:1;margin:.8rem 0}"
        html << "p,dl{color:color-mix(in srgb,currentColor 72%,transparent)}"
        html << "dt{font-weight:700}dd{margin:0 0 1rem;overflow-wrap:anywhere}"
        html << "footer{margin-top:3rem;font-size:.875rem}"
        html << "</style></head><body><header>via</header><main>"
        html << "<h1>#{code}</h1><h2>"
        ::HTML.escape(title, html)
        html << "</h2><p>"
        ::HTML.escape(message, html)
        html << "</p>"
        html << details if details
        html << "</main><footer>Request ID: "
        ::HTML.escape(request_id, html)
        html << "</footer></body></html>"
      end
    end
  end
end
