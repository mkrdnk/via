module Via::HTTP
  module ForwardedHeaders
    extend self

    HOP_BY_HOP = {
      "Connection",
      "Keep-Alive",
      "Proxy-Authenticate",
      "Proxy-Authorization",
      "TE",
      "Trailer",
      "Transfer-Encoding",
      "Upgrade",
    }

    def filter(source : ::HTTP::Headers) : ::HTTP::Headers
      headers = source.dup

      if connection = headers["Connection"]?
        connection.split(',').each do |name|
          headers.delete(name.strip)
        end
      end

      HOP_BY_HOP.each { |name| headers.delete(name) }
      headers
    end

    def request(
      request : ::HTTP::Request,
      upstream : URI,
      request_id : String,
      scheme : String,
      rules : Routing::HeaderRules = Routing::HeaderRules.new,
    ) : ::HTTP::Headers
      headers = filter(request.headers)
      original_host = request.headers["Host"]?

      headers["Host"] = upstream_authority(upstream)
      headers["X-Request-ID"] = request_id
      if original_host
        headers["X-Forwarded-Host"] = original_host
      else
        headers.delete("X-Forwarded-Host")
      end
      headers["X-Forwarded-Proto"] = scheme

      if address = request.remote_address
        if address.is_a?(Socket::IPAddress)
          append_forwarded_for(headers, address.address)
        end
      end

      apply(headers, rules)
      headers
    end

    def copy_response(
      source : ::HTTP::Headers,
      destination : ::HTTP::Headers,
      rules : Routing::HeaderRules = Routing::HeaderRules.new,
    ) : Nil
      filter(source).each do |name, values|
        values.each { |value| destination.add(name, value) }
      end
      apply(destination, rules)
    end

    def valid_host?(request : ::HTTP::Request) : Bool
      host = request.headers["Host"]?
      return false if request.version == "HTTP/1.1" && host.nil?
      return true unless host

      !Routing::Router.normalize_request_host(host).nil?
    end

    private def apply(headers : ::HTTP::Headers, rules : Routing::HeaderRules) : Nil
      rules.remove.each { |name| headers.delete(name) }
      rules.set.each { |name, value| headers[name] = value }
    end

    private def append_forwarded_for(headers : ::HTTP::Headers, client_ip : String) : Nil
      if forwarded_for = headers["X-Forwarded-For"]?.try(&.presence)
        headers["X-Forwarded-For"] = "#{forwarded_for}, #{client_ip}"
      else
        headers["X-Forwarded-For"] = client_ip
      end
    end

    private def upstream_authority(upstream : URI) : String
      hostname = upstream.hostname.not_nil!
      hostname = "[#{hostname}]" if hostname.includes?(':')
      port = upstream.port
      default_port = upstream.scheme == "https" ? 443 : 80

      port && port != default_port ? "#{hostname}:#{port}" : hostname
    end
  end
end
