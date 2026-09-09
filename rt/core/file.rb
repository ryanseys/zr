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

  # The fields of stat(2) at one moment, read once.
  class Stat
    include Comparable

    FIELDS = %i[dev ino mode nlink uid gid rdev size blksize blocks].freeze
    attr_reader(*FIELDS)

    def initialize(path)
      fields = Primitive.zr_stat_m(path, true)
      raise SystemCallError.new("@ rb_file_s_stat - #{path}", -fields) if fields.is_a?(Integer)

      take(fields)
    end

    def atime = Time.at(@atime_s, @atime_ns, :nsec)
    def mtime = Time.at(@mtime_s, @mtime_ns, :nsec)
    def ctime = Time.at(@ctime_s, @ctime_ns, :nsec)
    def birthtime = ctime

    def ftype
      case @mode & 0o170000
      when 0o040000 then "directory"
      when 0o100000 then "file"
      when 0o120000 then "link"
      when 0o020000 then "characterSpecial"
      when 0o060000 then "blockSpecial"
      when 0o010000 then "fifo"
      when 0o140000 then "socket"
      else "unknown"
      end
    end

    def directory? = ftype == "directory"
    def file? = ftype == "file"
    def symlink? = ftype == "link"
    def pipe? = ftype == "fifo"
    def socket? = ftype == "socket"
    def chardev? = ftype == "characterSpecial"
    def blockdev? = ftype == "blockSpecial"
    def size? = @size.zero? ? nil : @size
    def zero? = @size.zero?
    def readable? = (@mode & 0o444) != 0
    def writable? = (@mode & 0o222) != 0
    def executable? = (@mode & 0o111) != 0
    def setuid? = (@mode & 0o4000) != 0
    def setgid? = (@mode & 0o2000) != 0
    def sticky? = (@mode & 0o1000) != 0
    def owned? = @uid == Process.uid

    def <=>(other)
      return nil unless other.is_a?(Stat)

      mtime <=> other.mtime
    end

    def inspect
      "#<File::Stat dev=0x#{@dev.to_s(16)}, ino=#{@ino}, mode=0#{@mode.to_s(8)}, nlink=#{@nlink}, uid=#{@uid}, gid=#{@gid}, " \
        "rdev=0x#{@rdev.to_s(16)}, size=#{@size}, blksize=#{@blksize}, blocks=#{@blocks}, " \
        "atime=#{atime}, mtime=#{mtime}, ctime=#{ctime}, birthtime=#{birthtime}>"
    end

    private

    def take(fields)
      @dev, @ino, @mode, @nlink, @uid, @gid, @rdev, @size, @blksize, @blocks,
        @atime_s, @atime_ns, @mtime_s, @mtime_ns, @ctime_s, @ctime_ns = fields
    end

    # Made from lstat(2), which does not follow a symbolic link.
    def self.link(path)
      fields = Primitive.zr_stat_m(path, false)
      raise SystemCallError.new("@ rb_file_s_lstat - #{path}", -fields) if fields.is_a?(Integer)

      allocate.tap { |stat| stat.send(:take, fields) }
    end
  end

  FNM_NOESCAPE = 1
  FNM_PATHNAME = 2
  FNM_DOTMATCH = 4
  FNM_CASEFOLD = 8
  FNM_EXTGLOB = 16
  FNM_SYSCASE = 0
  FNM_SHORTNAME = 0

  # A shell pattern against a path: `*`, `?` and `[...]` never cross a
  # `/` under FNM_PATHNAME, where `**/` also stands for any run of
  # directories; a leading dot needs FNM_DOTMATCH; `\` escapes unless
  # FNM_NOESCAPE; braces alternate under FNM_EXTGLOB.
  def self.fnmatch(pattern, path, flags = 0)
    pattern = path_of(pattern)
    path = path_of(path)
    patterns = (flags & FNM_EXTGLOB).zero? ? [pattern] : Dir.const_get(:Glob).expand_braces(pattern)
    patterns.any? { |p| fnmatch_regexp(p, flags).match?(path) }
  end

  def self.fnmatch?(pattern, path, flags = 0) = fnmatch(pattern, path, flags)

  def self.fnmatch_regexp(pattern, flags)
    Primitive.attr! :hidden
    pathname = (flags & FNM_PATHNAME) != 0
    dotmatch = (flags & FNM_DOTMATCH) != 0
    escape = (flags & FNM_NOESCAPE).zero?
    one = pathname ? "[^/]" : "."
    nodot = dotmatch ? "" : "(?!\\.)"
    out = +"\\A"
    i = 0
    at_start = true
    while i < pattern.size
      c = pattern[i]
      case c
      when "*"
        if pathname && pattern[i, 3] == "**/" && (i.zero? || pattern[i - 1] == "/")
          out << (dotmatch ? "(?:[^/]*/)*" : "(?:(?!\\.)[^/]*/)*")
          i += 3
          at_start = true
          next
        end
        out << nodot if at_start
        out << "#{one}*"
      when "?"
        out << nodot if at_start
        out << one
      when "["
        close = pattern.index("]", i + 2)
        if close.nil?
          out << "\\["
        else
          out << nodot if at_start
          set = pattern[(i + 1)...close]
          set = "^#{set[1..]}" if set.start_with?("!")
          set = set.gsub("\\", "\\\\\\\\") if escape
          out << "[#{set}]"
          i = close
        end
      when "\\"
        if escape && i + 1 < pattern.size
          i += 1
          out << Regexp.escape(pattern[i])
        else
          out << "\\\\"
        end
      else
        out << Regexp.escape(c)
      end
      at_start = c == "/" && pathname
      i += 1
    end
    Regexp.new("#{out}\\z", (flags & FNM_CASEFOLD).zero? ? 0 : Regexp::IGNORECASE)
  end
  private_class_method :fnmatch_regexp

  def self.stat(path) = Stat.new(path_of(path))
  def self.lstat(path) = Stat.link(path_of(path))
  def self.mtime(path) = stat(path).mtime
  def self.atime(path) = stat(path).atime
  def self.ctime(path) = stat(path).ctime
  def self.ftype(path) = lstat(path).ftype
  def self.symlink?(path) = Primitive.zr_stat_m(path_of(path), false).then { |f| f.is_a?(Array) && (f[2] & 0o170000) == 0o120000 }

  def self.realpath(path, dir = nil)
    path = path_of(path)
    path = File.join(path_of(dir), path) if dir && !path.start_with?("/")
    result = Primitive.zr_realpath_m(path)
    raise SystemCallError.new("@ rb_check_realpath_internal - #{path}", -result) if result.is_a?(Integer)

    result
  end

  def self.chmod(mode, *paths)
    paths.each do |path|
      result = Primitive.zr_chmod_m(path_of(path), mode)
      raise SystemCallError.new("@ apply2files - #{path}", -result) if result < 0
    end
    paths.size
  end

  # A path argument: a String, or what `to_path` or `to_str` answers.
  def self.path_of(path)
    Primitive.attr! :hidden
    return path if path.is_a?(String)
    return path.to_path if path.respond_to?(:to_path)

    String.try_convert(path) or raise TypeError, "no implicit conversion of #{path.class} into String"
  end
  private_class_method :path_of

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

  # `glob(patterns, flags, base:, sort:)`: every path a pattern names,
  # per pattern in order, each pattern's matches sorted. A pattern is
  # split on `/`; `**` walks every directory below; braces expand
  # first; the other pieces match a name as File.fnmatch does with
  # FNM_PATHNAME, hidden names only under FNM_DOTMATCH or a literal dot.
  def self.glob(patterns, flags = 0, base: nil, sort: true)
    patterns = Array(patterns)
    found = patterns.flat_map do |pattern|
      pattern = File.send(:path_of, pattern)
      Glob.expand_braces(pattern).flat_map { |p| Glob.new(p, flags, base).run }.uniq
    end
    return found unless block_given?

    found.each { |path| yield path }
    nil
  end

  def self.[](*patterns, base: nil, sort: true)
    glob(patterns, base: base, sort: sort)
  end

  # One brace-free pattern matched against the file system.
  class Glob
    def initialize(pattern, flags, base)
      @flags = flags
      @base = base && !pattern.start_with?("/") ? File.send(:path_of, base) : nil
      @root = pattern.start_with?("/") ? "/" : (@base || ".")
      @dirs_only = pattern.end_with?("/")
      @segments = pattern.split("/").reject(&:empty?)
    end

    # The paths found, relative to the base when one was given, sorted.
    def run
      return [] if @segments.empty?

      out = []
      walk(@root, 0, out)
      out.map! { |path| path.delete_prefix("#{@base}/") } if @base
      out.sort
    end

    def self.expand_braces(pattern)
      open = pattern.index("{")
      return [pattern] if open.nil?

      depth = 0
      close = nil
      (open...pattern.size).each do |i|
        depth += 1 if pattern[i] == "{"
        depth -= 1 if pattern[i] == "}"
        if depth.zero?
          close = i
          break
        end
      end
      return [pattern] if close.nil?

      choices = []
      depth = 0
      piece = +""
      pattern[(open + 1)...close].each_char do |c|
        depth += 1 if c == "{"
        depth -= 1 if c == "}"
        if c == "," && depth.zero?
          choices << piece
          piece = +""
        else
          piece << c
        end
      end
      choices << piece
      choices.flat_map { |choice| expand_braces(pattern[0...open] + choice + pattern[(close + 1)..]) }
    end

    private

    # The paths under `dir` that match the segments from `i` on. A
    # `**` before more segments stands for zero or more directories; a
    # last `**` matches like `*`.
    def walk(dir, i, out)
      segment = @segments[i]
      last = i == @segments.size - 1
      if segment == "**" && (!last || @dirs_only)
        walk(dir, i + 1, out) unless last
        each_entry(dir) do |_, path|
          next unless File.directory?(path) && !File.symlink?(path)

          found(path, out) if last
          walk(path, i, out)
        end
      elsif literal?(segment)
        path = join(dir, segment)
        return unless File.exist?(path) || File.symlink?(path)

        last ? found(path, out) : walk(path, i + 1, out)
      else
        pattern = segment == "**" ? "*" : segment
        each_entry(dir, last) do |name, path|
          next unless File.fnmatch?(pattern, name, @flags | File::FNM_PATHNAME)

          if last
            found(path, out)
          elsif File.directory?(path)
            walk(path, i + 1, out)
          end
        end
      end
    end

    # A match goes out; a pattern ending in `/` wants only directories,
    # each with its slash.
    def found(path, out)
      return out << path unless @dirs_only

      out << "#{path}/" if File.directory?(path)
    end

    # The names in `dir`, hidden ones only under FNM_DOTMATCH, which
    # also offers `.` itself to a last segment.
    def each_entry(dir, last = false)
      names = begin
        Dir.children(dir)
      rescue SystemCallError
        return
      end
      names.unshift(".") if last && dotmatch?
      names.sort.each do |name|
        next if name.start_with?(".") && !dotmatch?

        yield name, join(dir, name)
      end
    end

    def literal?(segment) = !segment.match?(/[*?\[\\]/)

    def dotmatch? = (@flags & File::FNM_DOTMATCH) != 0

    def join(dir, name)
      return name if dir == "."
      return "/#{name}" if dir == "/"

      "#{dir}/#{name}"
    end
  end
  private_constant :Glob
  # With a block, the directory changes back afterwards; without one
  # it stays. No argument means the home directory.
  def self.chdir(path = nil)
    if path.nil?
      path = ENV["HOME"] || ENV["LOGDIR"]
      raise ArgumentError, "HOME/LOGDIR not set" if path.nil?
    end
    path = path.to_path if path.respond_to?(:to_path)
    return move_to(path) unless block_given?

    before = pwd
    move_to(path)
    begin
      yield path
    ensure
      move_to(before)
    end
  end

  def self.move_to(path)
    Primitive.attr! :hidden
    result = Primitive.zr_io_chdir(path)
    raise SystemCallError.new("@ chdir_path - #{path}", -result) if result < 0

    0
  end
  private_class_method :move_to
  def self.home(*) = Primitive.zr_unimplemented("Dir.home")
  def self.tmpdir = Primitive.zr_unimplemented("Dir.tmpdir")
end
