module Via
  class RouteConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter host : String?
    getter path : String = "/"

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter listen : String

    @[YAML::Field(key: "proxy_pass")]
    getter proxy_pass : String?

    getter routes : Array(RouteConfig)?

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
