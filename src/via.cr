require "http/client"
require "http/server"
require "yaml"

require "./via/config"
require "./via/router"
require "./via/config_validator"
require "./via/request_id"
require "./via/error_pages"
require "./via/client_pool"
require "./via/proxy"
require "./via/server"
require "./via/cli"

module Via
  VERSION = "0.1.0"
end
