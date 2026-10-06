module Via::HTTP::ServerHeader
  VALUE = "Via"

  def self.apply(headers : ::HTTP::Headers) : Nil
    headers["Server"] = VALUE
  end
end
