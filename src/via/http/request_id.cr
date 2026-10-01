require "random/secure"

module Via::HTTP
  module RequestId
    BYTES = 16

    def self.generate : String
      Random::Secure.hex(BYTES)
    end
  end
end
