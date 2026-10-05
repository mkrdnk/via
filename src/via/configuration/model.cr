module Via::Configuration
  class Timeouts
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter connect : String?
    getter read : String?
    getter write : String?

    def initialize(
      @connect : String? = nil,
      @read : String? = nil,
      @write : String? = nil,
    )
    end
  end

  class Shutdown
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter websocket_timeout : String?

    def initialize(@websocket_timeout : String? = nil)
    end
  end

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
  alias ReturnValue = String | Int32

  class Route
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter host : String?
    getter path : String = "/"

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : ProxyPass?

    @[YAML::Field(key: "static")]
    getter static_config : String | Static | Nil

    @[YAML::Field(key: "return")]
    getter return_config : ReturnValue?

    getter timeouts : Timeouts?
  end

  class Model
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String?
    getter host : String?
    getter debug : Bool?
    getter log_file : String?
    getter log_level : String?

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : ProxyPass?

    getter routes : Array(Route)?
    getter tls : TLS?
    getter timeouts : Timeouts?
    getter shutdown : Shutdown?

    @[YAML::Field(ignore: true)]
    property config_file : String?

    def initialize(
      @listen : String? = nil,
      @debug : Bool? = nil,
      @log_file : String? = nil,
      @log_level : String? = nil,
      @proxy_pass : ProxyPass? = nil,
      @routes : Array(Route)? = nil,
      @tls : TLS? = nil,
      @timeouts : Timeouts? = nil,
      @host : String? = nil,
      @config_file : String? = nil,
      @shutdown : Shutdown? = nil,
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
