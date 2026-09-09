# File and Dir: the path functions, which are pure, and what a program
# asks the file system.
class File < IO
  SEPARATOR = "/"
  ALT_SEPARATOR = nil
  PATH_SEPARATOR = ":"

  def self.basename(path, suffix = nil)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    return "/" if path.delete("/").empty? && !path.empty?

    name = path.split("/").reject(&:empty?).last || ""
    return name if suffix.nil? || name == suffix

    if suffix == ".*"
      dot = name.rindex(".")
      return dot && dot > 0 ? name[0, dot] : name
    end
    name.end_with?(suffix) ? name[0, name.size - suffix.size] : name
  end

  def self.dirname(path, level = 1)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    level.times do
      parts = path.split("/").reject(&:empty?)
      parts.pop
      path = if parts.empty? then path.start_with?("/") ? "/" : "."
             else (path.start_with?("/") ? "/" : "") + parts.join("/")
             end
    end
    path
  end

  def self.extname(path)
    name = basename(path)
    dot = name.rindex(".")
    return "" if dot.nil? || dot == 0 || dot == name.size - 1

    name[dot..]
  end

  def self.split(path) = [dirname(path), basename(path)]

  def self.join(*parts)
    parts.flatten.each_with_index.map do |part, i|
      raise TypeError, "no implicit conversion of #{part.class} into String" unless part.is_a?(String)

      part = part.delete_prefix("/") if i > 0 && part.start_with?("/")
      part = part.delete_suffix("/") if i < parts.size - 1 && part.end_with?("/") && part.size > 1
      part
    end.join("/")
  end

  def self.absolute_path?(path) = path.start_with?("/")

  def self.expand_path(path, dir = nil)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)
    Primitive.zr_unimplemented("File.expand_path with a home directory") if path.start_with?("~") || (dir && dir.start_with?("~"))

    base = if path.start_with?("/") then ""
           elsif dir.nil? then Dir.pwd
           elsif dir.start_with?("/") then dir
           else "#{Dir.pwd}/#{dir}"
           end
    parts = []
    "#{base}/#{path}".split("/").each do |part|
      case part
      when "", "." then nil
      when ".." then parts.pop
      else parts << part
      end
    end
    "/" + parts.join("/")
  end

  def self.absolute_path(path, dir = nil) = expand_path(path, dir)

  def self.exist?(path) = Primitive.zr_path_kind(path) != 0
  def self.file?(path) = Primitive.zr_path_kind(path) == 2
  def self.directory?(path) = Primitive.zr_path_kind(path) == 1

  RDONLY = 0
  WRONLY = 1
  RDWR = 2
  APPEND = 8
  CREAT = 512
  TRUNC = 1024
  EXCL = 2048
  NONBLOCK = 4
  MODES = %w[r r+ w w+ a a+].freeze
  private_constant :MODES

  # A mode string ("r", "w+", "ab", ...) or open(2) flags.
  def self.open(path, mode = "r", perm = 0o666, **options, &block)
    file = new(path, mode, perm, **options)
    return file unless block

    begin
      yield file
    ensure
      file.close
    end
  end

  def initialize(path, mode = "r", perm = 0o666, **options)
    Primitive.zr_unimplemented("File.new with options") unless options.empty? || options.keys == [:mode]
    mode = options[:mode] if options.key?(:mode)
    path = path.to_path if path.respond_to?(:to_path)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    text = File.send(:open_mode, mode)
    stream = Primitive.zr_io_open(path, text)
    raise SystemCallError.new("@ rb_sysopen - #{path}", -stream) if stream < 0

    super(Primitive.zr_io_fileno(stream), text, path: path)
    @stream = stream
  end

  # fclose closes the descriptor with the stream.
  def close
    return nil if closed?

    stream = @stream
    @stream = nil
    Primitive.zr_io_fclose(stream) if stream
    send(:mark_closed)
    nil
  end

  def self.read(path, length = nil, offset = nil, **options)
    open(path, "r", **options) do |file|
      file.seek(offset) if offset
      length ? file.read(length) : file.read
    end
  end

  def self.write(path, content, offset = nil, mode: nil, **options)
    open(path, mode || (offset ? "r+" : "w"), **options) do |file|
      file.seek(offset) if offset
      file.write(content)
    end
  end

  def self.readlines(path, *args, **options)
    open(path) { |file| file.readlines(*args, **options) }
  end

  def self.foreach(path, *args, **options, &block)
    return to_enum(:foreach, path, *args, **options) unless block

    open(path) { |file| file.each_line(*args, **options, &block) }
    nil
  end

  def self.size(path)
    result = Primitive.zr_io_file_size(path)
    raise SystemCallError.new("@ rb_file_s_size - #{path}", -result) if result < 0

    result
  end

  def self.size?(path)
    result = Primitive.zr_io_file_size(path)
    result <= 0 ? nil : result
  end

  def self.zero?(path) = Primitive.zr_io_file_size(path) == 0
  def self.empty?(path) = zero?(path)

  def self.readable?(path) = Primitive.zr_path_access(path, 4)
  def self.writable?(path) = Primitive.zr_path_access(path, 2)
  def self.executable?(path) = Primitive.zr_path_access(path, 1)

  def self.delete(*paths)
    paths.each do |path|
      result = Primitive.zr_io_unlink(path)
      raise SystemCallError.new("@ apply2files - #{path}", -result) if result < 0
    end
    paths.size
  end

  def self.unlink(*paths) = delete(*paths)

  def self.rename(from, to)
    result = Primitive.zr_io_rename(from, to)
    raise SystemCallError.new("@ rb_file_s_rename - (#{from}, #{to})", -result) if result < 0

    0
  end

  def self.mtime(path) = Primitive.zr_unimplemented("File.mtime")
  def self.stat(path) = Primitive.zr_unimplemented("File.stat")
  def self.symlink?(path) = Primitive.zr_unimplemented("File.symlink?")
  def self.realpath(path, dir = nil) = Primitive.zr_unimplemented("File.realpath")
  def self.chmod(mode, *paths) = Primitive.zr_unimplemented("File.chmod")

  def size = File.size(path)

  def to_path = path

  class << self
    private

    # The fopen mode for a Ruby mode string or open(2) flags.
    def open_mode(mode)
      if mode.is_a?(Integer)
        return "a+" if mode & APPEND != 0 && mode & RDWR == RDWR
        return "a" if mode & APPEND != 0
        return "w+" if mode & RDWR == RDWR && mode & TRUNC != 0
        return "r+" if mode & RDWR == RDWR
        return mode & TRUNC != 0 || mode & CREAT != 0 ? "w" : "r" if mode & WRONLY != 0

        return "r"
      end
      text = mode.to_str.delete("bt")
      text = text.split(":").first || "" if text.include?(":")
      raise ArgumentError, "invalid access mode #{mode}" unless MODES.include?(text)

      text
    end
  end
end

class Dir
  def self.pwd = Primitive.zr_getcwd
  def self.getwd = pwd
  def self.exist?(path) = Primitive.zr_path_kind(path) == 1

  def self.mkdir(path, mode = 0o777)
    result = Primitive.zr_io_mkdir(path, mode)
    raise SystemCallError.new("@ dir_s_mkdir - #{path}", -result) if result < 0

    0
  end

  def self.rmdir(path)
    result = Primitive.zr_io_rmdir(path)
    raise SystemCallError.new("@ dir_s_rmdir - #{path}", -result) if result < 0

    0
  end

  def self.unlink(path) = rmdir(path)
  def self.delete(path) = rmdir(path)

  # Every name in the directory, `.` and `..` among them.
  def self.entries(path)
    names = Primitive.zr_io_dir_names(path)
    raise SystemCallError.new("@ dir_initialize - #{path}", -names) if names.is_a?(Integer)

    names
  end

  def self.children(path) = entries(path).reject { |name| name == "." || name == ".." }

  def self.each_child(path, &block)
    return to_enum(:each_child, path) unless block

    children(path).each(&block)
    nil
  end

  def self.foreach(path, &block)
    return to_enum(:foreach, path) unless block

    entries(path).each(&block)
    nil
  end

  def self.empty?(path) = children(path).empty?

  def self.glob(*) = Primitive.zr_unimplemented("Dir.glob")
  def self.[](*) = Primitive.zr_unimplemented("Dir[]")
  def self.chdir(*) = Primitive.zr_unimplemented("Dir.chdir")
  def self.home(*) = Primitive.zr_unimplemented("Dir.home")
  def self.tmpdir = Primitive.zr_unimplemented("Dir.tmpdir")
end
