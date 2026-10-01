require "spec"
require "file/tempfile"
require "file_utils"
require "../src/via"

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
