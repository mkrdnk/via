require "base64"

module Via::HTTP
  module Favicon
    SVG      = {{ read_file("#{__DIR__}/../../../web/docs/assets/favicon.svg") }}
    DATA_URI = "data:image/svg+xml;base64,#{Base64.strict_encode(SVG)}"
  end
end
