module Via
  module ErrorPages
    record Definition, title : String, message : String

    DEFINITIONS = {
      HTTP::Status::BAD_REQUEST => Definition.new(
        "Bad Request",
        "The request could not be understood."
      ),
      HTTP::Status::NOT_FOUND => Definition.new(
        "Not Found",
        "The requested resource was not found."
      ),
      HTTP::Status::BAD_GATEWAY => Definition.new(
        "Bad Gateway",
        "The upstream server could not be reached."
      ),
      HTTP::Status::SERVICE_UNAVAILABLE => Definition.new(
        "Service Unavailable",
        "The service is temporarily unavailable."
      ),
      HTTP::Status::GATEWAY_TIMEOUT => Definition.new(
        "Gateway Timeout",
        "The upstream server did not respond in time."
      ),
    }

    def self.body(status : HTTP::Status, request_id : String) : String
      definition = DEFINITIONS[status]? ||
                   raise ArgumentError.new("No error page for HTTP #{status.code}")

      String.build do |body|
        body << "via\n\n"
        body << status.code << '\n'
        body << definition.title << "\n\n"
        body << definition.message << "\n\n"
        body << "Request ID: " << request_id << '\n'
      end
    end

    def self.render(
      response : HTTP::Server::Response,
      status : HTTP::Status,
      request_id : String,
      *,
      head : Bool = false,
    ) : Nil
      content = body(status, request_id)
      response.headers.clear
      response.status = status
      response.content_type = "text/plain; charset=utf-8"
      response.content_length = content.bytesize
      response.headers["X-Request-ID"] = request_id
      response << content unless head
    end
  end
end
