module Via::Logging
  enum Level
    Debug
    Info
    Warn
    Error

    def self.parse_config(value : String) : self?
      case value.upcase
      when "DEBUG"           then Debug
      when "INFO"            then Info
      when "WARN", "WARNING" then Warn
      when "ERROR"           then Error
      end
    end

    def label : String
      to_s.downcase
    end
  end
end
