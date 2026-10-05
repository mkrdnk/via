require "spec"
require "file/tempfile"
require "file_utils"
require "../src/via"

# Keep examples concise while production code uses explicit module boundaries.
module Via
  alias Config = Configuration::Model
  alias ConfigLoader = Configuration::Loader
  alias ConfigReloader = Configuration::Reloader
  alias ConfigWatcher = Configuration::Watcher
  alias ConfigValidator = Configuration::Validator
  alias ConfigurationError = Configuration::Error
  alias ListenAddress = Configuration::ListenAddress
  alias RoutingTimeouts = Routing::Timeouts
  alias StaticConfig = Configuration::Static
  alias TlsConfig = Configuration::TLS
  alias ValidatedConfig = Configuration::Validated

  alias Route = Routing::Route
  alias Router = Routing::Router
  alias StaticTarget = Routing::StaticTarget

  alias ErrorPages = HTTP::ErrorPages
  alias ForwardedHeaders = HTTP::ForwardedHeaders
  alias RequestId = HTTP::RequestId

  alias RuntimeState = Runtime::State
  alias StaticFiles = Static::Files
  alias Tls = TLS::ContextBuilder
end

module ViaSpecHelpers
  private def with_server(server : HTTP::Server, &)
    address = server.bind_unused_port
    spawn server.listen
    yield address
  ensure
    server.close
  end

  private def with_temp_directory(&)
    path = File.tempname("via-spec", "")
    Dir.mkdir(path)
    yield path
  ensure
    FileUtils.rm_rf(path) if path && File.exists?(path)
  end
end

include ViaSpecHelpers
