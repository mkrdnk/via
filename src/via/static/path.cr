module Via::Static
  module Path
    extend self

    def canonical_root(path : String) : String
      File.realpath(path)
    end

    def normalize_relative(path : String, *, allow_empty : Bool = false) : String?
      return if path.includes?('\0') || path.includes?('\\')
      return if ::Path[path].absolute?

      segments = path.split('/')
      return if segments.includes?("..")

      segments.reject!(&.in?("", "."))
      return if segments.empty? && !allow_empty

      segments.join(File::SEPARATOR)
    end

    def resolve(root : String, relative_path : String) : Tuple(String, File::Info)?
      expanded = File.expand_path(relative_path, root)
      return unless inside_root?(root, expanded)
      return unless File.info?(expanded)

      real_path = File.realpath(expanded)
      return unless inside_root?(root, real_path)
      info = File.info?(real_path)
      return unless info

      {real_path, info}
    rescue File::Error
      nil
    end

    def inside_root?(root : String, path : String) : Bool
      path == root || path.starts_with?("#{root}#{File::SEPARATOR}")
    end
  end
end
