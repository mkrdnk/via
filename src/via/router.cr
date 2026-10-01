module Via
  record StaticTarget, root : String, fallback : String?
  record Route,
    host : String?,
    path : String,
    upstream : URI?,
    static_target : StaticTarget? = nil

  # Selects a route without depending on HTTP server or client types.
  #
  # Paths use segment-aware prefix matching. The longest matching path wins;
  # for equal paths an exact host route wins over a hostless route. Remaining
  # ties preserve configuration order.
  class Router
    def initialize(routes : Enumerable(Route))
      @routes = routes.to_a
      raise ArgumentError.new("router requires at least one route") if @routes.empty?
    end

    def match(host : String?, path : String) : Route?
      request_host = self.class.normalize_request_host(host)
      best = nil

      @routes.each do |route|
        next unless host_matches?(route.host, request_host)
        next unless path_matches?(route.path, path)

        current = best
        best = route if current.nil? || more_specific?(route, current)
      end

      best
    end

    def self.normalize_request_host(authority : String?) : String?
      return unless authority

      uri = URI.parse("http://#{authority.strip}")
      hostname = uri.hostname
      return unless hostname && !hostname.empty? && uri.path.empty? &&
                    uri.query.nil? && uri.fragment.nil? && uri.user.nil? &&
                    uri.password.nil?

      normalize_hostname(hostname)
    rescue URI::Error
      nil
    end

    def self.normalize_hostname(hostname : String) : String
      hostname.downcase.rstrip('.')
    end

    private def host_matches?(route_host : String?, request_host : String?) : Bool
      route_host.nil? || route_host == request_host
    end

    private def path_matches?(route_path : String, request_path : String) : Bool
      route_path == "/" ||
        request_path == route_path ||
        request_path.starts_with?("#{route_path}/")
    end

    private def more_specific?(candidate : Route, current : Route) : Bool
      return true if candidate.path.bytesize > current.path.bytesize
      return false if candidate.path.bytesize < current.path.bytesize

      !candidate.host.nil? && current.host.nil?
    end
  end
end
