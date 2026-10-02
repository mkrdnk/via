require "set"
require "uri"

module Via::Configuration
  class Validator
    def initialize(@config : Model)
    end

    def validate : Validated
      listen = validate_listen
      routes = build_routes
      reject_duplicate_routes(routes)
      tls = validate_tls
      Validated.new(listen, routes, tls)
    end

    def validate_listen : ListenAddress
      value = @config.listen ||
              raise Error.new("Configuration requires listen")
      parse_listen(value)
    end

    def validate_tls : TLS?
      return unless tls = @config.tls

      validate_tls_file(tls.cert, "tls.cert")
      validate_tls_file(tls.key, "tls.key")
      tls
    end

    private def build_routes : Array(Routing::Route)
      proxy_pass = @config.proxy_pass
      route_configs = @config.routes

      if proxy_pass && route_configs
        raise Error.new("Use either proxy_pass or routes, not both")
      end

      if proxy_pass
        return [build_proxy_route(nil, "/", proxy_pass)]
      end

      unless route_configs && !route_configs.empty?
        raise Error.new("Configuration requires proxy_pass or at least one route")
      end

      route_configs.map_with_index do |route, index|
        upstream = route.proxy_pass
        static_config = route.static_config
        if upstream && static_config
          raise Error.new(
            "routes[#{index}] must use either proxy_pass or static, not both"
          )
        end
        unless upstream || static_config
          raise Error.new(
            "routes[#{index}] requires proxy_pass or static"
          )
        end

        host = parse_host(route.host, index)
        path = parse_path(route.path, index)
        if upstream
          build_proxy_route(host, path, upstream, "routes[#{index}].proxy_pass")
        else
          Routing::Route.new(
            host,
            path,
            nil,
            parse_static(static_config.not_nil!, index)
          )
        end
      end
    end

    private def build_proxy_route(
      host : String?,
      path : String,
      value : ProxyPass,
      field = "proxy_pass",
    ) : Routing::Route
      case value
      when String
        Routing::Route.new(host, path, parse_upstream(value, field))
      when Int32
        Routing::Route.new(
          host,
          path,
          nil,
          nil,
          parse_response_status(value, field)
        )
      else
        raise "Unsupported proxy_pass value"
      end
    end

    private def parse_listen(value : String) : ListenAddress
      uri = URI.parse("tcp://#{value}")
      port = uri.port
      host = uri.hostname

      unless port && port.in?(1..65_535) && host &&
             (host.empty? || valid_hostname?(host)) && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil?
        raise Error.new("Invalid listen address: #{value}")
      end

      host = "0.0.0.0" if host.empty?
      ListenAddress.new(host, port)
    rescue URI::Error
      raise Error.new("Invalid listen address: #{value}")
    end

    private def parse_host(value : String?, route_index : Int32) : String?
      return unless value

      uri = URI.parse("http://#{value.strip}")
      hostname = uri.hostname
      normalized = hostname.try { |host| Routing::Router.normalize_hostname(host) }

      unless hostname && valid_hostname?(hostname) && normalized && !normalized.empty? &&
             uri.port.nil? && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil? && uri.user.nil? && uri.password.nil?
        raise Error.new("Invalid host in routes[#{route_index}]: #{value}")
      end

      normalized
    rescue URI::Error
      raise Error.new("Invalid host in routes[#{route_index}]: #{value}")
    end

    private def parse_path(value : String, route_index : Int32) : String
      unless value.starts_with?('/') && !value.includes?('?') && !value.includes?('#')
        raise Error.new("Invalid path in routes[#{route_index}]: #{value}")
      end

      normalized = value
      while normalized.size > 1 && normalized.ends_with?('/')
        normalized = normalized.rchop
      end
      normalized
    end

    private def parse_upstream(value : String, field = "proxy_pass") : URI
      uri = URI.parse(value)
      host = uri.hostname

      unless uri.scheme.in?("http", "https") && host && valid_hostname?(host) &&
             uri.user.nil? && uri.password.nil? && uri.query.nil? && uri.fragment.nil? &&
             (uri.path.empty? || uri.path == "/")
        raise Error.new("Invalid upstream URL in #{field}: #{value}")
      end

      uri.path = ""
      uri
    rescue URI::Error
      raise Error.new("Invalid upstream URL in #{field}: #{value}")
    end

    private def parse_response_status(value : Int32, field : String) : Int32
      unless value.in?(200..599)
        raise Error.new("Invalid response status in #{field}: #{value} (expected 200..599)")
      end

      value
    end

    private def parse_static(value : String | Static, route_index : Int32) : Routing::StaticTarget
      config = value.is_a?(String) ? Static.new(value) : value
      root = begin
        ::Via::Static::Path.canonical_root(config.root)
      rescue File::Error
        raise Error.new(
          "Static root in routes[#{route_index}] is not a readable directory: #{config.root}"
        )
      end

      unless File.directory?(root) && File::Info.readable?(root)
        raise Error.new(
          "Static root in routes[#{route_index}] is not a readable directory: #{config.root}"
        )
      end

      fallback = config.fallback
      if fallback
        fallback = validate_static_fallback(root, fallback, route_index)
      end

      Routing::StaticTarget.new(root, fallback)
    end

    private def validate_static_fallback(
      root : String,
      fallback : String,
      route_index : Int32,
    ) : String
      normalized = ::Via::Static::Path.normalize_relative(fallback)
      unless normalized
        raise Error.new(
          "Invalid static fallback in routes[#{route_index}]: #{fallback}"
        )
      end

      resolved = ::Via::Static::Path.resolve(root, normalized)
      unless resolved && resolved[1].file? && File::Info.readable?(resolved[0])
        raise Error.new(
          "Static fallback in routes[#{route_index}] is not a readable file: #{fallback}"
        )
      end

      normalized
    end

    private def reject_duplicate_routes(routes : Array(Routing::Route)) : Nil
      seen = Set(Tuple(String?, String)).new

      routes.each do |route|
        key = {route.host, route.path}
        unless seen.add?(key)
          description = route.host ? "#{route.host}#{route.path}" : route.path
          raise Error.new("Duplicate route: #{description}")
        end
      end
    end

    private def valid_hostname?(hostname : String) : Bool
      !hostname.empty? && hostname.each_char.none?(&.whitespace?)
    end

    private def validate_tls_file(path : String, field : String) : Nil
      if path.empty?
        raise Error.new("#{field} must not be empty")
      end
      info = File.info?(path)
      unless info && info.file? && File::Info.readable?(path)
        raise Error.new("#{field} is not a readable file: #{path}")
      end
    end
  end
end
