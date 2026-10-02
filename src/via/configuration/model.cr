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

  alias ProxyPass = String | Int32

  class Route
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter host : String?
    getter path : String = "/"

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : ProxyPass?

    @[YAML::Field(key: "static")]
    getter static_config : String | Static | Nil
  end

  class Model
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String?
    getter host : String?
    getter log_file : String?
    getter log_level : String?

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : ProxyPass?

    getter routes : Array(Route)?
    getter tls : TLS?

    @[YAML::Field(ignore: true)]
    property config_file : String?

    def initialize(
      @listen : String? = nil,
      @log_file : String? = nil,
      @log_level : String? = nil,
      @proxy_pass : ProxyPass? = nil,
      @routes : Array(Route)? = nil,
      @tls : TLS? = nil,
      @host : String? = nil,
      @config_file : String? = nil,
    )
    end

    def self.load(path : String) : self
      model = File.open(path) { |file| from_yaml(file) }
      model.config_file = path
      model
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
