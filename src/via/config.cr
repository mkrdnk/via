require "uri"

module Via
  class ConfigurationError < Exception
  end

  record ListenAddress, host : String, port : Int32 do
    def self.parse(value : String) : self
      uri = URI.parse("tcp://#{value}")
      port = uri.port
      host = uri.hostname

      unless port && port.in?(1..65_535) && host && uri.path.empty? &&
             uri.query.nil? && uri.fragment.nil?
        raise ConfigurationError.new("Invalid listen address: #{value}")
      end

      host = "0.0.0.0" if host.empty?
      new(host, port)
    rescue URI::Error
      raise ConfigurationError.new("Invalid listen address: #{value}")
    end
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String

    def self.load(path : String) : self
      File.open(path) { |file| from_yaml(file) }
    rescue ex : File::Error
      raise ConfigurationError.new("Could not read configuration #{path}: #{ex.message}")
    rescue ex : YAML::Error
      raise ConfigurationError.new("Invalid configuration #{path}: #{ex.message}")
    end

    def validate : ValidatedConfig
      address = ListenAddress.parse(listen)
      upstream = parse_upstream(proxy_pass)
      ValidatedConfig.new(address, upstream)
    end

    private def parse_upstream(value : String) : URI
      uri = URI.parse(value)
      host = uri.hostname

      unless uri.scheme.in?("http", "https") && host && !host.empty? && uri.user.nil? &&
             uri.password.nil? && uri.query.nil? && uri.fragment.nil? &&
             (uri.path.empty? || uri.path == "/")
        raise ConfigurationError.new("Invalid upstream URL: #{value}")
      end

      uri
    rescue URI::Error
      raise ConfigurationError.new("Invalid upstream URL: #{value}")
    end
  end

  record ValidatedConfig, listen : ListenAddress, upstream : URI
end
