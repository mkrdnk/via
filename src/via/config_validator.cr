require "set"
require "uri"

module Via
  class ConfigurationError < Exception
  end

  record ListenAddress, host : String, port : Int32
  record ValidatedConfig,
    listen : ListenAddress,
    routes : Array(Route),
    tls : TlsConfig? = nil

  class ConfigValidator
    def initialize(@config : Config)
    end

    def validate : ValidatedConfig
      listen = validate_listen
      routes = build_routes
      reject_duplicate_routes(routes)
      tls = validate_tls
      ValidatedConfig.new(listen, routes, tls)
    end

    def validate_listen : ListenAddress
      value = @config.listen ||
              raise ConfigurationError.new("Configuration requires listen")
      parse_listen(value)
    end

    def validate_tls : TlsConfig?
      return unless tls = @config.tls

      validate_tls_file(tls.cert, "tls.cert")
      validate_tls_file(tls.key, "tls.key")
      tls
    end

    private def build_routes : Array(Route)
      proxy_pass = @config.proxy_pass
      route_configs = @config.routes

      if proxy_pass && route_configs
        raise ConfigurationError.new("Use either proxy_pass or routes, not both")
      end

      if proxy_pass
        return [Route.new(nil, "/", parse_upstream(proxy_pass))]
      end

      unless route_configs && !route_configs.empty?
        raise ConfigurationError.new("Configuration requires proxy_pass or at least one route")
      end

      route_configs.map_with_index do |route, index|
        Route.new(
          parse_host(route.host, index),
          parse_path(route.path, index),
          parse_upstream(route.proxy_pass, "routes[#{index}].proxy_pass")
        )
      end
    end

    private def parse_listen(value : String) : ListenAddress
      uri = URI.parse("tcp://#{value}")
      port = uri.port
      host = uri.hostname

      unless port && port.in?(1..65_535) && host &&
             (host.empty? || valid_hostname?(host)) && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil?
        raise ConfigurationError.new("Invalid listen address: #{value}")
      end

      host = "0.0.0.0" if host.empty?
      ListenAddress.new(host, port)
    rescue URI::Error
      raise ConfigurationError.new("Invalid listen address: #{value}")
    end

    private def parse_host(value : String?, route_index : Int32) : String?
      return unless value

      uri = URI.parse("http://#{value.strip}")
      hostname = uri.hostname
      normalized = hostname.try { |host| Router.normalize_hostname(host) }

      unless hostname && valid_hostname?(hostname) && normalized && !normalized.empty? &&
             uri.port.nil? && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil? && uri.user.nil? && uri.password.nil?
        raise ConfigurationError.new("Invalid host in routes[#{route_index}]: #{value}")
      end

      normalized
    rescue URI::Error
      raise ConfigurationError.new("Invalid host in routes[#{route_index}]: #{value}")
    end

    private def parse_path(value : String, route_index : Int32) : String
      unless value.starts_with?('/') && !value.includes?('?') && !value.includes?('#')
        raise ConfigurationError.new("Invalid path in routes[#{route_index}]: #{value}")
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
        raise ConfigurationError.new("Invalid upstream URL in #{field}: #{value}")
      end

      uri.path = ""
      uri
    rescue URI::Error
      raise ConfigurationError.new("Invalid upstream URL in #{field}: #{value}")
    end

    private def reject_duplicate_routes(routes : Array(Route)) : Nil
      seen = Set(Tuple(String?, String)).new

      routes.each do |route|
        key = {route.host, route.path}
        unless seen.add?(key)
          description = route.host ? "#{route.host}#{route.path}" : route.path
          raise ConfigurationError.new("Duplicate route: #{description}")
        end
      end
    end

    private def valid_hostname?(hostname : String) : Bool
      !hostname.empty? && hostname.each_char.none?(&.whitespace?)
    end

    private def validate_tls_file(path : String, field : String) : Nil
      if path.empty?
        raise ConfigurationError.new("#{field} must not be empty")
      end
      info = File.info?(path)
      unless info && info.file? && File::Info.readable?(path)
        raise ConfigurationError.new("#{field} is not a readable file: #{path}")
      end
    end
  end
end
