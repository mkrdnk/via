require "mime"

module Via::Static
  module Files
    extend self

    def call(
      context : ::HTTP::Server::Context,
      route_path : String,
      target : Routing::StaticTarget,
      request_id : String,
    ) : Nil
      request = context.request
      unless request.method.in?("GET", "HEAD")
        method_not_allowed(context, request_id)
        return
      end

      relative_path = relative_path(request.path, route_path)
      unless relative_path
        not_found(context, request_id)
        return
      end

      resolved = Path.resolve(target.root, relative_path)
      if resolved && resolved[1].directory?
        unless request.path.ends_with?('/')
          redirect_to_directory(context)
          return
        end
        resolved = Path.resolve(target.root, File.join(relative_path, "index.html"))
      end

      unless resolved && resolved[1].file?
        resolved = target.fallback.try { |fallback| Path.resolve(target.root, fallback) }
      end

      unless resolved && resolved[1].file?
        not_found(context, request_id)
        return
      end

      serve(context, resolved[0], resolved[1], request_id)
    rescue URI::Error
      not_found(context, request_id)
    end

    private def relative_path(request_path : String, route_path : String) : String?
      decoded = URI.decode(request_path)
      return if decoded.includes?('\0') || decoded.includes?('\\')

      relative = if route_path == "/"
                   decoded.lchop('/')
                 else
                   decoded.byte_slice(route_path.bytesize..).lchop('/')
                 end

      Path.normalize_relative(relative, allow_empty: true)
    end

    private def redirect_to_directory(context : ::HTTP::Server::Context) : Nil
      uri = context.request.uri.dup
      uri.path = "#{context.request.path}/"
      context.response.redirect(uri, :moved_permanently)
    end

    private def serve(
      context : ::HTTP::Server::Context,
      path : String,
      info : File::Info,
      request_id : String,
    ) : Nil
      response = context.response
      etag = etag(info)
      response.content_type = MIME.from_filename(path, "application/octet-stream")
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["ETag"] = etag
      response.headers["Last-Modified"] = ::HTTP.format_time(info.modification_time)

      if not_modified?(context.request, etag, info.modification_time)
        response.status = :not_modified
        return
      end

      if range_header = context.request.headers["Range"]?
        range = parse_range(range_header, info.size)
        unless range
          range_not_satisfiable(context, info.size, request_id)
          return
        end
        serve_range(context, path, range, info.size, request_id)
      else
        response.content_length = info.size
        copy_file(context, path, info.size, request_id) unless context.request.method == "HEAD"
      end
    end

    private def serve_range(
      context : ::HTTP::Server::Context,
      path : String,
      range : Range(Int64, Int64),
      file_size : Int64,
      request_id : String,
    ) : Nil
      response = context.response
      length = range.size
      response.status = :partial_content
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{file_size}"
      response.content_length = length
      return if context.request.method == "HEAD"

      File.open(path) do |file|
        file.seek(range.begin)
        IO.copy(file, response, length)
      end
    rescue File::Error
      not_found(context, request_id)
    end

    private def copy_file(
      context : ::HTTP::Server::Context,
      path : String,
      size : Int64,
      request_id : String,
    ) : Nil
      File.open(path) { |file| IO.copy(file, context.response, size) }
    rescue File::Error
      not_found(context, request_id)
    end

    private def parse_range(header : String, file_size : Int64) : Range(Int64, Int64)?
      value = header.lchop?("bytes=")
      return unless value && !value.includes?(',') && file_size > 0

      start_text, separator, end_text = value.partition('-')
      return if separator.empty?

      if start_text.empty?
        suffix = end_text.to_i64?
        return unless suffix && suffix > 0
        start = Math.max(file_size - suffix, 0_i64)
        return start..(file_size - 1)
      end

      start = start_text.to_i64?
      return unless start && start >= 0 && start < file_size
      finish = end_text.empty? ? file_size - 1 : end_text.to_i64?
      return unless finish && finish >= start

      start..Math.min(finish, file_size - 1)
    end

    private def not_modified?(request : ::HTTP::Request, etag : String, modified_at : Time) : Bool
      if header = request.headers["If-None-Match"]?
        return header.split(',').any? { |candidate| candidate.strip.in?("*", etag) }
      end

      if header = request.headers["If-Modified-Since"]?
        if timestamp = ::HTTP.parse_time(header)
          return modified_at <= timestamp + 1.second
        end
      end

      false
    end

    private def etag(info : File::Info) : String
      %{W/"#{info.modification_time.to_unix_ns}-#{info.size}"}
    end

    private def method_not_allowed(
      context : ::HTTP::Server::Context,
      request_id : String,
    ) : Nil
      Via::HTTP::ErrorPages.render(
        context.response,
        ::HTTP::Status::METHOD_NOT_ALLOWED,
        request_id,
        additional_headers: ::HTTP::Headers{"Allow" => "GET, HEAD"}
      )
    end

    private def range_not_satisfiable(
      context : ::HTTP::Server::Context,
      file_size : Int64,
      request_id : String,
    ) : Nil
      Via::HTTP::ErrorPages.render(
        context.response,
        ::HTTP::Status::RANGE_NOT_SATISFIABLE,
        request_id,
        head: context.request.method == "HEAD",
        additional_headers: ::HTTP::Headers{
          "Accept-Ranges" => "bytes",
          "Content-Range" => "bytes */#{file_size}",
        }
      )
    end

    private def not_found(context : ::HTTP::Server::Context, request_id : String) : Nil
      Via::HTTP::ErrorPages.render(
        context.response,
        ::HTTP::Status::NOT_FOUND,
        request_id,
        head: context.request.method == "HEAD"
      )
    end
  end
end
