module Via
  class TlsConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter cert : String
    getter key : String

    def initialize(@cert : String, @key : String)
    end
  end

  class StaticConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter root : String
    getter fallback : String?

    def initialize(@root : String, @fallback : String? = nil)
    end
  end

  class RouteConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter host : String?
    getter path : String = "/"

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String?

    @[YAML::Field(key: "static")]
    getter static_config : String | StaticConfig | Nil
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String?

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String?

    getter routes : Array(RouteConfig)?
    getter tls : TlsConfig?

    def initialize(
      @listen : String? = nil,
      @proxy_pass : String? = nil,
      @routes : Array(RouteConfig)? = nil,
      @tls : TlsConfig? = nil,
    )
    end

    def self.load(path : String) : self
      File.open(path) { |file| from_yaml(file) }
    rescue ex : File::Error
      raise ConfigurationError.new("Could not read configuration #{path}: #{ex.message}")
    rescue ex : YAML::Error
      raise ConfigurationError.new("Invalid configuration #{path}: #{ex.message}")
    end

    def validate : ValidatedConfig
      ConfigValidator.new(self).validate
    end
  end
end
