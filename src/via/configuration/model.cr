module Via::Configuration
  class TLS
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter cert : String
    getter key : String

    def initialize(@cert : String, @key : String)
    end
  end

  class Static
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter root : String
    getter fallback : String?

    def initialize(@root : String, @fallback : String? = nil)
    end
  end

  class Route
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter host : String?
    getter path : String = "/"

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String?

    @[YAML::Field(key: "static")]
    getter static_config : String | Static | Nil
  end

  class Model
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String?

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String?

    getter routes : Array(Route)?
    getter tls : TLS?

    def initialize(
      @listen : String? = nil,
      @proxy_pass : String? = nil,
      @routes : Array(Route)? = nil,
      @tls : TLS? = nil,
    )
    end

    def self.load(path : String) : self
      File.open(path) { |file| from_yaml(file) }
    rescue ex : File::Error
      raise Error.new("Could not read configuration #{path}: #{ex.message}")
    rescue ex : YAML::Error
      raise Error.new("Invalid configuration #{path}: #{ex.message}")
    end

    def validate : Validated
      Validator.new(self).validate
    end
  end
end
