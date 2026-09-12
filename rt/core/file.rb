# File and Dir: the path functions, which are pure, and what a program
# asks the file system.
class File < IO
  # ruby names this module File::Constants and IO takes it by
  # inclusion, so File::APPEND and IO::APPEND are one constant.
  module Constants
    RDONLY = 0
    WRONLY = 1
    RDWR = 2
    NONBLOCK = 4
    APPEND = 8
    SHARE_DELETE = 0
    SYNC = 128
    DSYNC = 4194304
    NOFOLLOW = 256
    CREAT = 512
    TRUNC = 1024
    EXCL = 2048
    NOCTTY = 131072
    BINARY = 0

    # flock(2): LOCK_SH 1, LOCK_EX 2, LOCK_UN 8, with LOCK_NB 4 added.
    LOCK_SH = 1
    LOCK_EX = 2
    LOCK_NB = 4
    LOCK_UN = 8

    FNM_NOESCAPE = 1
    FNM_PATHNAME = 2
    FNM_DOTMATCH = 4
    FNM_CASEFOLD = 8
    FNM_EXTGLOB = 16
    FNM_SYSCASE = 0
    FNM_SHORTNAME = 0

    NULL = "/dev/null"
  end

  include Constants

  SEPARATOR = "/"
  ALT_SEPARATOR = nil
  PATH_SEPARATOR = ":"

  def self.basename(path, suffix = nil)
    path = path_of(path)

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
    path = path_of(path)

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
    lead = 0
    lead += 1 while lead < name.size && name[lead] == "."
    dot = name.rindex(".")
    return "" if dot.nil? || dot < lead

    name[dot..]
  end

  def self.split(path) = [dirname(path), basename(path)]

  # ruby's rb_file_join: one separator at each seam, taken from
  # whichever side already carries one, so "a//" and "//b" meet as
  # "a//b" and not "a////b".
  def self.join(*parts)
    out = +""
    parts.flatten.each_with_index do |part, i|
      part = Primitive.zr_str_operand(part.respond_to?(:to_path) ? part.to_path : part)
      if i.positive?
        if part.start_with?("/")
          out.sub!(%r{/+\z}, "")
        elsif !out.end_with?("/")
          out << "/"
        end
      end
      out << part
    end
    out
  end

  def self.absolute_path?(path) = path.start_with?("/")

  def self.expand_path(path, dir = nil)
    path = expand_home(path_of(path))
    dir = expand_home(path_of(dir)) if dir
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

  # `~` and `~user` at the front name a home directory.
  def self.expand_home(path)
    Primitive.attr! :hidden
    return path unless path.start_with?("~")

    name = path[1..].split("/", 2).first
    home = name.nil? || name.empty? ? Dir.home : Dir.home(name)
    rest = path[(name.nil? ? 1 : name.size + 1)..]
    rest.nil? || rest.empty? ? home : "#{home}#{rest}"
  end
  private_class_method :expand_home

  def self.absolute_path(path, dir = nil) = expand_path(path, dir)

  def self.exist?(path) = Primitive.zr_path_kind(path_of(path)) != 0
  def self.file?(path) = Primitive.zr_path_kind(path_of(path)) == 2
  def self.directory?(path) = Primitive.zr_path_kind(path_of(path)) == 1

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
    mode = options[:mode] if options.key?(:mode)
    perm = options[:perm] if options.key?(:perm)
    path = File.send(:path_of, path)

    # The descriptor opens by the access mode alone; the mode and the
    # options go on to IO, which reads the encodings they name.
    text = File.send(:open_mode, mode)
    made = !File.exist?(path)
    if mode.is_a?(Integer) && (mode & File::CREAT) != 0
      raise Errno::EEXIST, "@ rb_sysopen - #{path}" if !made && (mode & File::EXCL) != 0

      # fopen makes a file only in a writing mode, so a creation that
      # keeps what is there opens a new file as "w+".
      text = "w+" if made && text == "r+"
    end
    if File.pipe?(path) && Primitive.zr_threaded && !Thread.send(:alone?)
      # open(2) on a FIFO waits for the other end, which would stop
      # every green thread. A task that shares the process opens the
      # descriptor without waiting and keeps it that way: every read
      # and write already asks the descriptor whether it is ready.
      super(fifo_fd(path, text), mode, **options, path: path)
      @nonblock = true
      return
    end

    stream = Primitive.zr_io_open(path, text)
    raise SystemCallError.new("@ rb_sysopen - #{path}", -stream) if stream < 0

    super(Primitive.zr_io_fileno(stream), mode, **options, path: path)
    Primitive.zr_io_chmod_fd(@fd, perm) if made && perm != 0o666
    @stream = stream
  end

  # fclose closes the descriptor with the stream; a stream-less file
  # closes its descriptor the way every other IO does.
  def close
    return nil if closed?
    return super unless @stream

    stream = @stream
    @stream = nil
    Primitive.zr_io_fclose(stream)
    send(:mark_closed)
    nil
  end

  # The descriptor for a FIFO, waited for a turn at a time. A write end
  # answers ENXIO until a reader shows up; a read end opens at once.
  def fifo_fd(path, text)
    Primitive.attr! :hidden
    flags = File.send(:open_flags, text) | File::NONBLOCK
    loop do
      fd = Primitive.zr_io_open_flags(path, flags)
      return fd if fd >= 0
      raise SystemCallError.new("@ rb_sysopen - #{path}", -fd) unless -fd == Errno::ENXIO::Errno

      sleep 0.001
    end
  end
  private :fifo_fd

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
    path = path_of(path)
    result = Primitive.zr_io_file_size(path)
    raise SystemCallError.new("@ rb_file_s_size - #{path}", -result) if result < 0

    result
  end

  def self.size?(path)
    result = Primitive.zr_io_file_size(path_of(path))
    result <= 0 ? nil : result
  end

  def self.zero?(path) = Primitive.zr_io_file_size(path_of(path)) == 0
  def self.empty?(path) = zero?(path)

  def self.readable?(path) = Primitive.zr_path_access(path_of(path), 4)
  def self.writable?(path) = Primitive.zr_path_access(path_of(path), 2)
  def self.executable?(path) = Primitive.zr_path_access(path_of(path), 1)

  def self.delete(*paths)
    paths.each do |path|
      path = path_of(path)
      result = Primitive.zr_io_unlink(path)
      raise SystemCallError.new("@ apply2files - #{path}", -result) if result < 0
    end
    paths.size
  end

  def self.unlink(*paths) = delete(*paths)

  def self.rename(from, to)
    from = path_of(from)
    to = path_of(to)
    result = Primitive.zr_io_rename(from, to)
    fail2(-result, "rb_file_s_rename", from, to) if result < 0

    0
  end

  # The fields of stat(2) at one moment, read once.
  class Stat
    include Comparable

    FIELDS = %i[dev ino mode nlink uid gid rdev size blksize blocks].freeze
    attr_reader(*FIELDS)

    def initialize(path, site = "rb_file_s_stat")
      path = File.send(:path_of, path)
      fields = Primitive.zr_stat_m(path, true)
      raise SystemCallError.new("@ #{site} - #{path}", -fields) if fields.is_a?(Integer)

      take(fields)
    end

    # A stream opened from a descriptor has no path, so fstat(2) is the
    # only way to its rows.
    def self.for_fd(fd)
      fields = Primitive.zr_fstat_m(fd)
      raise SystemCallError.new("@ rb_io_stat - fd #{fd}", -fields) if fields.is_a?(Integer)

      allocate.send(:take, fields)
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
    def grpowned? = @gid == Process.gid
    def world_readable? = (@mode & 0o004) != 0 ? @mode & 0o777 : nil
    def world_writable? = (@mode & 0o002) != 0 ? @mode & 0o777 : nil
    def readable_real? = readable?
    def writable_real? = writable?
    def executable_real? = executable?

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
      self
    end

    # Made from lstat(2), which does not follow a symbolic link.
    def self.link(path)
      path = File.send(:path_of, path)
      fields = Primitive.zr_stat_m(path, false)
      raise SystemCallError.new("@ rb_file_s_lstat - #{path}", -fields) if fields.is_a?(Integer)

      allocate.tap { |stat| stat.send(:take, fields) }
    end
  end

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
        source, close = char_class(pattern, i, escape, one)
        out << nodot if at_start && close
        out << source
        i = close if close
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

  # An atom no character matches: an empty set, and a `[` that never
  # closes, both of which fnmatch reads as a pattern nothing satisfies.
  NOTHING = "[^\\s\\S]"
  private_constant :NOTHING

  # A `[...]` set as fnmatch reads it: `!` or `^` right after the bracket
  # negates, the first `]` closes even with nothing before it, `\` escapes
  # unless FNM_NOESCAPE, and `[:name:]` is six ordinary characters.
  # Answers the regexp source and the closing bracket's index.
  def self.char_class(pattern, open, escape, one)
    Primitive.attr! :hidden
    i = open + 1
    negated = pattern[i] == "!" || pattern[i] == "^"
    i += 1 if negated
    body = +""
    while i < pattern.size && pattern[i] != "]"
      i += 1 if escape && pattern[i] == "\\" && i + 1 < pattern.size
      body << (pattern[i] == "-" ? "-" : Regexp.escape(pattern[i]))
      i += 1
    end
    return [NOTHING, nil] if i >= pattern.size
    return [negated ? one : NOTHING, i] if body.empty?

    ["(?#{negated ? '!' : '='}[#{body}])#{one}", i]
  end
  private_class_method :char_class


  def self.stat(path) = Stat.new(path_of(path))
  def self.lstat(path) = Stat.link(path_of(path))
  def self.mtime(path) = Stat.new(path_of(path), "rb_file_s_mtime").mtime
  def self.atime(path) = Stat.new(path_of(path), "rb_file_s_atime").atime
  def self.ctime(path) = Stat.new(path_of(path), "rb_file_s_ctime").ctime
  def self.ftype(path) = lstat(path).ftype
  def self.symlink?(path) = Primitive.zr_stat_m(path_of(path), false).then { |f| f.is_a?(Array) && (f[2] & 0o170000) == 0o120000 }

  def self.realpath(path, dir = nil)
    path = path_of(path)
    path = File.join(path_of(dir), path) if dir && !path.start_with?("/")
    result = Primitive.zr_realpath_m(path)
    raise SystemCallError.new("@ rb_check_realpath_internal - #{path}", -result) if result.is_a?(Integer)

    result
  end

  def self.chmod(mode, *paths) = each_path(paths) { |path| Primitive.zr_chmod_m(path, mode) }

  def self.lchmod(mode, *paths) = each_path(paths) { |path| Primitive.zr_fs_call(9, path, mode, 0) }

  def self.chown(owner, group, *paths) = each_path(paths) { |path| Primitive.zr_fs_call(0, path, owner || -1, group || -1) }

  def self.lchown(owner, group, *paths) = each_path(paths) { |path| Primitive.zr_fs_call(1, path, owner || -1, group || -1) }

  # utime takes its times in seconds, as Integers, Floats or Times.
  def self.utime(atime, mtime, *paths)
    a = microseconds(atime)
    m = microseconds(mtime)
    each_path(paths) { |path| Primitive.zr_utimes_m(path, a, m) }
  end

  def self.microseconds(time)
    Primitive.attr! :hidden
    (time.is_a?(Time) ? time.to_r : Rational(time)).*(1_000_000).round
  end
  private_class_method :microseconds

  # The block over each path, answering how many it touched; the first
  # failure raises with CRuby's own `apply2files` label.
  def self.each_path(paths)
    Primitive.attr! :hidden
    paths.each do |path|
      result = yield(path_of(path))
      raise SystemCallError.new("@ apply2files - #{path}", -result) if result < 0
    end
    paths.size
  end
  private_class_method :each_path

  def self.link(from, to)
    result = Primitive.zr_fs_call(2, path_of(from), path_of(to), 0)
    fail2(-result, "rb_file_s_link", from, to) if result < 0

    0
  end

  def self.symlink(from, to)
    result = Primitive.zr_fs_call(3, path_of(from), path_of(to), 0)
    fail2(-result, "rb_file_s_symlink", from, to) if result < 0

    0
  end

  # Ruby names both paths, except where the entry is already there:
  # then the message names the second path alone, under the helper that
  # decides.
  def self.fail2(code, site, from, to)
    raise SystemCallError.new("@ syserr_fail2_in - #{to}", code) if code == Errno::EEXIST::Errno

    raise SystemCallError.new("@ #{site} - (#{from}, #{to})", code)
  end
  private_class_method :fail2

  def self.readlink(path)
    result = Primitive.zr_readlink_m(path_of(path))
    raise SystemCallError.new("@ rb_readlink - #{path}", -result) if result.is_a?(Integer)

    result
  end

  def self.mkfifo(path, mode = 0o666)
    result = Primitive.zr_fs_call(4, path_of(path), mode, 0)
    raise SystemCallError.new("@ mkfifo - #{path}", -result) if result < 0

    0
  end

  def self.truncate(path, length)
    result = Primitive.zr_fs_call(5, path_of(path), length, 0)
    raise SystemCallError.new("@ rb_file_s_truncate - #{path}", -result) if result < 0

    0
  end

  def self.umask(mask = nil) = Primitive.zr_umask_m(mask)

  def self.birthtime(path) = Stat.new(path_of(path), "rb_file_s_birthtime").birthtime

  def self.blockdev?(path) = mode_kind?(path, 0o060000)
  def self.chardev?(path) = mode_kind?(path, 0o020000)
  def self.pipe?(path) = mode_kind?(path, 0o010000)
  def self.socket?(path) = mode_kind?(path, 0o140000)

  def self.mode_kind?(path, kind)
    Primitive.attr! :hidden
    fields = Primitive.zr_stat_m(path_of(path), true)
    fields.is_a?(Array) && (fields[2] & 0o170000) == kind
  end
  private_class_method :mode_kind?

  # The permission bits when everyone may read (or write) the file,
  # else nil.
  def self.world_readable?(path) = mode_when(path, 0o004)
  def self.world_writable?(path) = mode_when(path, 0o002)

  def self.mode_when(path, bit)
    Primitive.attr! :hidden
    fields = Primitive.zr_stat_m(path_of(path), true)
    return nil unless fields.is_a?(Array) && (fields[2] & bit) != 0

    fields[2] & 0o7777
  end
  private_class_method :mode_when

  def self.setuid?(path) = mode_set?(path, 0o4000)
  def self.setgid?(path) = mode_set?(path, 0o2000)
  def self.sticky?(path) = mode_set?(path, 0o1000)

  def self.mode_set?(path, bit)
    Primitive.attr! :hidden
    fields = Primitive.zr_stat_m(path_of(path), true)
    fields.is_a?(Array) && (fields[2] & bit) != 0
  end
  private_class_method :mode_set?

  def self.owned?(path) = stat_field(path, 4) == Process.uid
  def self.grpowned?(path) = stat_field(path, 5) == Process.gid

  def self.stat_field(path, index)
    Primitive.attr! :hidden
    fields = Primitive.zr_stat_m(path_of(path), true)
    fields.is_a?(Array) ? fields[index] : nil
  end
  private_class_method :stat_field

  # The same file: one device and one inode.
  def self.identical?(a, b)
    left = Primitive.zr_stat_m(path_of(a), true)
    right = Primitive.zr_stat_m(path_of(b), true)
    left.is_a?(Array) && right.is_a?(Array) && left[0] == right[0] && left[1] == right[1]
  end

  # `access(2)` answers for the real user, which is the one the plain
  # forms ask about too.
  def self.readable_real?(path) = readable?(path)
  def self.writable_real?(path) = writable?(path)
  def self.executable_real?(path) = executable?(path)

  def self.path(object) = path_of(object)

  # `realpath` where the last name need not exist.
  def self.realdirpath(path, dir = nil)
    path = path_of(path)
    path = File.join(path_of(dir), path) if dir && !path.start_with?("/")
    return realpath(path) if exist?(path)

    File.join(realpath(dirname(path)), basename(path))
  end

  # A path argument, as CRuby's rb_get_path takes it: a String, or what
  # `to_path` or `to_str` answers, with no NUL byte in it.
  def self.path_of(path)
    Primitive.attr! :hidden
    unless path.is_a?(String)
      given = path.respond_to?(:to_path) ? path.to_path : path
      path = String.try_convert(given) or raise TypeError, "no implicit conversion of #{given.nil? ? 'nil' : given.class} into String"
    end
    raise ArgumentError, "path name contains null byte" if path.include?("\0")

    path
  end
  private_class_method :path_of

  def size = File.size(path)

  def to_path = path

  def stat = File.stat(path)
  def lstat = File.lstat(path)
  def atime = stat.atime
  def mtime = stat.mtime
  def ctime = stat.ctime
  def birthtime = stat.birthtime

  def chmod(mode)
    result = Primitive.zr_fs_call(7, "", fileno, mode)
    raise SystemCallError.new("@ rb_file_chmod - #{path}", -result) if result < 0

    0
  end

  def chown(owner, group)
    File.chown(owner, group, path)
    0
  end

  def truncate(length)
    send(:check_writable)
    result = Primitive.zr_fs_call(6, "", fileno, length)
    raise SystemCallError.new("@ rb_file_truncate - #{path}", -result) if result < 0

    0
  end


  def flock(operation)
    result = Primitive.zr_fs_call(8, "", fileno, operation)
    return false if result == -Errno::EWOULDBLOCK::Errno

    raise SystemCallError.new("@ rb_file_flock - #{path}", -result) if result < 0

    0
  end

  class << self
    private

    # The fopen mode for a Ruby mode string or open(2) flags.
    def open_mode(mode)
      if mode.is_a?(Integer)
        # A singleton method's scope does not reach what the class
        # includes, so the flags are named through their module.
        append, rdwr, trunc, creat, wronly = Constants::APPEND, Constants::RDWR, Constants::TRUNC, Constants::CREAT, Constants::WRONLY
        return "a+" if mode & append != 0 && mode & rdwr == rdwr
        return "a" if mode & append != 0
        return "w+" if mode & rdwr == rdwr && mode & trunc != 0
        return "r+" if mode & rdwr == rdwr
        return mode & trunc != 0 || mode & creat != 0 ? "w" : "r" if mode & wronly != 0

        return "r"
      end
      string = String.try_convert(mode)
      raise TypeError, "no implicit conversion of #{mode.nil? ? 'nil' : mode.class} into String" if string.nil?

      text = string.delete("bt")
      text = text.split(":").first || "" if text.include?(":")
      raise ArgumentError, "invalid access mode #{mode}" unless MODES.include?(text)

      text
    end

    # The open(2) flags a fopen mode names.
    def open_flags(text)
      flags = if text.include?("+")
                Constants::RDWR
              else
                text.start_with?("r") ? Constants::RDONLY : Constants::WRONLY
              end
      flags |= Constants::CREAT | Constants::TRUNC if text.start_with?("w")
      flags |= Constants::CREAT | Constants::APPEND if text.start_with?("a")
      flags
    end
  end
end

# `FileTest` asks the same questions File does, as a module a program can
# mix in. Ruby gives both the one set of answers.
module FileTest
  module_function

  %i[blockdev? chardev? directory? empty? executable? executable_real? exist? file? grpowned?
     identical? owned? pipe? readable? readable_real? setgid? setuid? size size? socket? sticky?
     symlink? world_readable? world_writable? writable? writable_real? zero?].each do |name|
    define_method(name) { |*args| File.public_send(name, *args) }
    module_function name
  end
end


class Dir
  include Enumerable

  # A directory reached through a descriptor: the path it was opened
  # under is not knowable, so the names come from the descriptor.
  def self.for_fd(fd)
    names = Primitive.zr_io_dir_names_fd(fd)
    raise SystemCallError.new("@ dir_s_for_fd", -names) if names.is_a?(Integer)

    allocate.send(:take_names, nil, names)
  end

  def self.fchdir(fd)
    result = Primitive.zr_io_fchdir(fd)
    raise SystemCallError.new("@ dir_s_fchdir", -result) if result < 0

    return 0 unless block_given?

    yield
  end

  # A Dir is the directory's names and a cursor over them, read once
  # when it opens.
  # CRuby writes Dir's opening and globbing in Ruby (its dir.rb), so
  # they answer their own parameters, under CRuby's names.
  def initialize(name, encoding: nil)
    Primitive.attr! :ruby
    @path = File.path(name)
    names = Primitive.zr_io_dir_names(@path)
    raise SystemCallError.new("@ dir_initialize - #{@path}", -names) if names.is_a?(Integer)

    take_names(@path, names)
  end

  def take_names(path, names)
    Primitive.attr! :hidden
    @path = path
    @names = names
    @pos = 0
    self
  end

  def self.open(name, encoding: nil, &block)
    Primitive.attr! :ruby
    dir = new(name, encoding: encoding)
    return dir unless block

    begin
      yield dir
    ensure
      dir.close
    end
  end

  attr_reader :path
  alias to_path path

  def inspect = "#<Dir:#{@path}>"

  def close
    @names = nil
    nil
  end

  def read
    open_names[@pos].tap { @pos += 1 if @pos < open_names.size }
  end

  # The cursor is the index of the next name. CRuby answers whatever
  # `telldir` gives, which is a cookie for `seek` and nothing more.
  def pos = @pos

  def tell = @pos

  def pos=(where)
    @pos = where
    where
  end

  def seek(where)
    @pos = where
    self
  end

  def rewind
    @pos = 0
    self
  end

  def each(&block)
    return to_enum(:each) { open_names.size } unless block

    rewind
    while (name = read)
      yield name
    end
    self
  end

  def children = open_names.reject { |name| name == "." || name == ".." }

  def each_child(&block)
    return to_enum(:each_child) { children.size } unless block

    children.each(&block)
    self
  end

  def fileno = Primitive.zr_unimplemented("Dir#fileno")

  # The names, or the error a closed directory answers with.
  def open_names
    Primitive.attr! :hidden
    @names or raise IOError, "closed directory"
  end
  private :open_names

  def self.pwd = Primitive.zr_getcwd
  def self.getwd = pwd
  def self.exist?(path) = Primitive.zr_path_kind(File.send(:path_of, path)) == 1

  def self.mkdir(path, mode = 0o777)
    path = File.send(:path_of, path)
    result = Primitive.zr_io_mkdir(path, mode)
    raise SystemCallError.new("@ dir_s_mkdir - #{path}", -result) if result < 0

    0
  end

  def self.rmdir(path)
    path = File.send(:path_of, path)
    result = Primitive.zr_io_rmdir(path)
    raise SystemCallError.new("@ dir_s_rmdir - #{path}", -result) if result < 0

    0
  end

  def self.unlink(path) = rmdir(path)
  def self.delete(path) = rmdir(path)

  # Every name in the directory, `.` and `..` among them. `encoding:`
  # names what the names are read as; the runtime reads the file system
  # in the one encoding, so the names are tagged with it.
  def self.entries(path, encoding: nil)
    path = File.send(:path_of, path)
    names = Primitive.zr_io_dir_names(path)
    raise SystemCallError.new("@ dir_initialize - #{path}", -names) if names.is_a?(Integer)
    return names unless encoding

    names.map { |name| name.dup.force_encoding(encoding) }
  end

  def self.children(path, encoding: nil)
    entries(path, encoding: encoding).reject { |name| name == "." || name == ".." }
  end

  def self.each_child(path, encoding: nil, &block)
    return to_enum(:each_child, path, encoding: encoding) unless block

    children(path, encoding: encoding).each(&block)
    nil
  end

  def self.foreach(path, encoding: nil, &block)
    return to_enum(:foreach, path, encoding: encoding) unless block

    entries(path, encoding: encoding).each(&block)
    nil
  end

  def self.empty?(path) = children(path).empty?

  # `glob(patterns, flags, base:, sort:)`: every path a pattern names,
  # per pattern in order, each pattern's matches sorted. A pattern is
  # split on `/`; `**` walks every directory below; braces expand
  # first; the other pieces match a name as File.fnmatch does with
  # FNM_PATHNAME, hidden names only under FNM_DOTMATCH or a literal dot.
  def self.glob(pattern, _flags = 0, flags: _flags, base: nil, sort: true)
    Primitive.attr! :ruby
    patterns = Array(pattern)
    found = patterns.flat_map do |pattern|
      pattern = File.send(:path_of, pattern)
      Glob.expand_braces(pattern).flat_map { |p| Glob.new(p, flags, base).run }.uniq
    end
    return found unless block_given?

    found.each { |path| yield path }
    nil
  end

  def self.[](*args, base: nil, sort: true)
    Primitive.attr! :ruby
    glob(args, base: base, sort: sort)
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
    move_to(path, "dir_chdir0")
    begin
      yield path
    ensure
      move_to(before)
    end
  end

  def self.move_to(path, site = "chdir_path")
    Primitive.attr! :hidden
    path = File.send(:path_of, path)
    result = Primitive.zr_io_chdir(path)
    raise SystemCallError.new("@ #{site} - #{path}", -result) if result < 0

    0
  end
  private_class_method :move_to
  # This process's home from the environment, a named user's from the
  # password file.
  def self.home(user = nil)
    return Primitive.zr_home_dir(nil) if user.nil? && ENV["HOME"].nil?
    return ENV["HOME"] if user.nil?

    raise TypeError, "no implicit conversion of #{user.class} into String" unless user.is_a?(String)

    Primitive.zr_home_dir(user) || raise(ArgumentError, "user #{user} doesn't exist")
  end
end

module Kernel
  # `test(command, file, other = nil)`: one letter naming the question
  # to ask about a file, as the shell's own test does.
  def test(command, file, other = nil)
    command = command.is_a?(String) ? command : command.chr
    case command
    when "b" then File.blockdev?(file)
    when "c" then File.chardev?(file)
    when "d" then File.directory?(file)
    when "e" then File.exist?(file)
    when "f" then File.file?(file)
    when "g" then File.setgid?(file)
    when "G" then File.grpowned?(file)
    when "k" then File.sticky?(file)
    when "l" then File.symlink?(file)
    when "o" then File.owned?(file)
    when "O" then File.owned?(file)
    when "p" then File.pipe?(file)
    when "r", "R" then File.readable?(file)
    when "S" then File.socket?(file)
    when "s" then File.size?(file)
    when "u" then File.setuid?(file)
    when "w", "W" then File.writable?(file)
    when "x", "X" then File.executable?(file)
    when "z" then File.zero?(file)
    when "A" then File.atime(file)
    when "C" then File.ctime(file)
    when "M" then File.mtime(file)
    when "-" then File.identical?(file, other)
    when "=" then File.mtime(file) == File.mtime(other)
    when "<" then File.mtime(file) < File.mtime(other)
    when ">" then File.mtime(file) > File.mtime(other)
    else raise ArgumentError, "unknown command '#{command}'"
    end
  end
  private :test
  module_function :test
end

IO.include(File::Constants)
