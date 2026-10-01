require "http/client"
require "http/server"
require "yaml"

require "./via/configuration/error"
require "./via/configuration/model"
require "./via/routing/route"
require "./via/configuration/validated"
require "./via/static/path"
require "./via/routing/router"
require "./via/configuration/validator"
require "./via/configuration/loader"
require "./via/tls/context_builder"
require "./via/http/request_id"
require "./via/http/favicon"
require "./via/http/error_pages"
require "./via/static/files"
require "./via/proxy/pool"
require "./via/http/forwarded_headers"
require "./via/proxy/handler"
require "./via/runtime/generation"
require "./via/runtime/state"
require "./via/tls/reloadable_server"
require "./via/configuration/watcher"
require "./via/configuration/reloader"
require "./via/console/banner"
require "./via/server"
require "./via/cli"

module Via
  VERSION = {{
              read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:"))
                .split(":")[1]
                .strip
            }}
end
