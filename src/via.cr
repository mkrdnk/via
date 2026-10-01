require "http/client"
require "http/server"
require "yaml"

require "./via/config"
require "./via/config_loader"
require "./via/router"
require "./via/config_validator"
require "./via/tls"
require "./via/request_id"
require "./via/error_pages"
require "./via/static_files"
require "./via/client_pool"
require "./via/proxy"
require "./via/runtime_state"
require "./via/reloadable_tls_server"
require "./via/config_watcher"
require "./via/config_reloader"
require "./via/server"
require "./via/cli"

module Via
  VERSION = "0.1.0"
end
