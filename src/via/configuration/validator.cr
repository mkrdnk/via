require "set"
require "uri"

module Via::Configuration
  class Validator
    DURATION_PATTERN = /\A(?<value>(?:\d+(?:\.\d*)?|\.\d+))(?<unit>ms|s|m|h)\z/

    def initialize(@config : Model)
    end

    def validate : Validated
      listen = validate_listen
      routes = build_routes
      reject_duplicate_routes(routes)
      tls = validate_tls
      log_file = validate_log_file
      log_level = validate_log_level
      Validated.new(
        listen,
        routes,
        tls,
        log_file,
        log_level,
        @config.config_file,
        @config.debug || false
      )
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

    def validate_log_file : String?
      return unless path = @config.log_file

      if path.strip.empty?
        raise Error.new("log_file must not be empty")
      end

      path
    end

    def validate_log_level : Logging::Level?
      return unless value = @config.log_level
      if level = Logging::Level.parse_config(value)
        return level
      end

      raise Error.new(
        "Invalid log_level: #{value} (expected DEBUG, INFO, WARN, or ERROR)"
      )
    end

    private def build_routes : Array(Routing::Route)
      proxy_pass = @config.proxy_pass
      route_configs = @config.routes
      top_level_host = @config.host
      default_timeouts = parse_timeouts(@config.timeouts, "timeouts")

      if proxy_pass && route_configs
        raise Error.new("Use either proxy_pass or routes, not both")
      end

      if top_level_host && !proxy_pass
        raise Error.new("host can only be used with top-level proxy_pass")
      end

      if proxy_pass
        host = parse_host(top_level_host, "host")
        return [build_proxy_route(host, "/", proxy_pass, timeouts: default_timeouts)]
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

        host = parse_host(route.host, "routes[#{index}].host")
        path = parse_path(route.path, index)
        if upstream
          if route.timeouts && !upstream.is_a?(String)
            raise Error.new("routes[#{index}].timeouts requires an upstream URL")
          end

          route_timeouts = merge_timeouts(
            default_timeouts,
            parse_timeouts(route.timeouts, "routes[#{index}].timeouts")
          )
          build_proxy_route(
            host,
            path,
            upstream,
            "routes[#{index}].proxy_pass",
            route_timeouts
          )
        else
          if route.timeouts
            raise Error.new("routes[#{index}].timeouts requires an upstream URL")
          end

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
      timeouts = Routing::Timeouts.new,
    ) : Routing::Route
      case value
      when String
        expanded = expand_upstream(value, host, field)
        Routing::Route.new(
          host,
          path,
          parse_upstream(expanded, field),
          timeouts: timeouts
        )
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

    private def parse_timeouts(
      config : Timeouts?,
      field : String,
    ) : Routing::Timeouts
      return Routing::Timeouts.new unless config

      Routing::Timeouts.new(
        connect: parse_duration(config.connect, "#{field}.connect"),
        read: parse_duration(config.read, "#{field}.read"),
        write: parse_duration(config.write, "#{field}.write")
      )
    end

    private def parse_duration(value : String?, field : String) : Time::Span?
      return unless value

      match = DURATION_PATTERN.match(value)
      unless match
        raise Error.new(
          "Invalid #{field}: #{value} (expected a positive duration using ms, s, m, or h)"
        )
      end

      amount = match["value"].to_f?
      unless amount
        raise Error.new(
          "Invalid #{field}: #{value} (duration is too large)"
        )
      end

      span = case match["unit"]
             when "ms"
               amount.milliseconds
             when "s"
               amount.seconds
             when "m"
               amount.minutes
             when "h"
               amount.hours
             else
               raise "Unsupported duration unit"
             end

      unless amount.finite? && span > Time::Span.zero
        raise Error.new(
          "Invalid #{field}: #{value} (expected a positive duration using ms, s, m, or h)"
        )
      end

      span
    rescue OverflowError
      raise Error.new(
        "Invalid #{field}: #{value} (duration is too large)"
      )
    end

    private def merge_timeouts(
      defaults : Routing::Timeouts,
      overrides : Routing::Timeouts,
    ) : Routing::Timeouts
      Routing::Timeouts.new(
        connect: overrides.connect || defaults.connect,
        read: overrides.read || defaults.read,
        write: overrides.write || defaults.write
      )
    end

    private def expand_upstream(value : String, host : String?, field : String) : String
      return value unless value.includes?("$host")

      unless host
        raise Error.new("$host in #{field} requires a configured host")
      end

      authority_host = host.includes?(':') ? "[#{host}]" : host
      value.gsub("$host", authority_host)
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

    private def parse_host(value : String?, field : String) : String?
      return unless value

      uri = URI.parse("http://#{value.strip}")
      hostname = uri.hostname
      normalized = hostname.try { |host| Routing::Router.normalize_hostname(host) }

      unless hostname && valid_hostname?(hostname) && normalized && !normalized.empty? &&
             uri.port.nil? && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil? && uri.user.nil? && uri.password.nil?
        raise Error.new("Invalid #{field}: #{value}")
      end

      normalized
    rescue URI::Error
      raise Error.new("Invalid #{field}: #{value}")
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
      !hostname.empty? &&
        !hostname.includes?('$') &&
        hostname.each_char.none?(&.whitespace?)
    end

    private def validate_tls_file(path : String, field : String) : Nil
      if path.empty?
        raise Error.new("#{field} must not be empty")
      end

      begin
        info = File.info(path)
        unless info.file?
          raise Error.new("#{field} is not a readable file: #{path}")
        end
        File.open(path) { }
      rescue File::Error
        raise Error.new("#{field} is not a readable file: #{path}")
      end
    end
  end
end
