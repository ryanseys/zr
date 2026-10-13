# frozen_string_literal: true

# File and Dir: the path functions, which are pure, and the file
# system calls of a program.
class File < IO
  Separator = "/"
  SEPARATOR = Separator
  ALT_SEPARATOR = nil
  PATH_SEPARATOR = ":"

  def self.basename(path, suffix = (none = true; nil))
    path = path_of(path)
    suffix = Primitive.zr_str_operand(suffix) unless none

    return +"/" if path.delete("/").empty? && !path.empty?

    name = path.split("/").reject(&:empty?).last || +""
    return name if suffix.nil? || name == suffix

    # ruby_enc_find_basename: the extension is past the leading dots, so
    # ".." and ".bashrc" keep their whole name.
    if suffix == +".*"
      lead = 0
      lead += 1 while lead < name.size && name[lead] == +"."
      dot = name.rindex(".")
      return dot && dot >= lead ? name[0, dot] : name
    end
    name.end_with?(suffix) ? name[0, name.size - suffix.size] : name
  end

  def self.dirname(path, level = 1)
    path = path_of(path)
    level = Primitive.zr_index_operand_m(level)
    raise ArgumentError, "negative level: #{level}" if level < 0

    # rb_file_dirname_n: each level drops the last name and the
    # separators before it. The separators inside the rest stay as they
    # were, and a run of them at the start is one root.
    level.times do
      root = path.start_with?("/")
      body = path.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
      cut = body.rindex("/")
      path = if cut then (root ? +"/" : +"") << body[0, cut].sub(%r{/+\z}, "")
             else root ? +"/" : +"."
             end
    end
    path
  end

  def self.extname(path)
    name = basename(path_of(path))
    lead = 0
    lead += 1 while lead < name.size && name[lead] == +"."
    dot = name.rindex(".")
    return +"" if dot.nil? || dot < lead

    name[dot..]
  end

  # The path converts once, for both parts.
  def self.split(path)
    path = path_of(path)
    [dirname(path), basename(path)]
  end

  # `DATA`: the main program's text after its `__END__` line, as a File
  # at that byte. ruby reads it from the script that it keeps open. A
  # binary has no script next to it, so its source text goes into a file
  # that is unlinked immediately, and the File returns the script's path
  # as ruby's does.
  def self.data(source, at, path)
    Primitive.attr! :hidden
    name = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr-data-#{Process.pid}-#{rand(1 << 32)}")
    file = File.new(name, File::RDWR | File::CREAT | File::EXCL, 0o600)
    File.unlink(name)
    file.write(source)
    file.pos = at
    file.instance_variable_set(:@path, path)
    file
  end

  # ruby's rb_file_join: one separator at each join, taken from
  # the side that already has one, so "a//" and "//b" join as
  # "a//b" and not "a////b".
  def self.join(*parts) = joined(parts, {}.compare_by_identity)

  # rb_file_join: an Array in the parts is joined first, and an Array
  # that contains itself is refused. The result is binary with no parts;
  # else it starts in the first part's encoding and takes the encoding
  # of each part it joins (fs_enc_check).
  def self.joined(parts, joining)
    Primitive.attr! :hidden
    out = +"".b
    joining[parts] = true
    parts.each_index do |i|
      part = parts[i]
      part = if part.is_a?(String) then part
             elsif part.is_a?(Array)
               raise ArgumentError, +"recursive array" if joining.key?(part)

               joined(part, joining)
             else Primitive.zr_str_operand(part.respond_to?(:to_path) ? part.to_path : part)
             end
      unless part.encoding.ascii_compatible?
        raise Encoding::CompatibilityError, "path name must be ASCII-compatible (#{part.encoding}): #{part.inspect}"
      end
      raise ArgumentError, +"string contains null byte" if nul_char?(part)
      if i.zero?
        out.force_encoding(part.encoding)
      elsif part.start_with?("/")
        out.sub!(%r{/+\z}, "")
      elsif !out.end_with?("/")
        out << "/"
      end
      encoding = Encoding.compatible?(out, part)
      encoding = out.encoding == Encoding::US_ASCII ? part.encoding : out.encoding if encoding == Encoding::US_ASCII
      out << part
      out.force_encoding(encoding) if encoding
    end
    joining.delete(parts)
    out
  end
  private_class_method :joined

  def self.absolute_path?(path) = path_of(path).start_with?("/")

  # The result is in the argument's encoding; a relative US-ASCII one takes
  # the encoding of the directory it joins. The working directory is in
  # the filesystem's, which has to be ASCII compatible to join them.
  def self.expand_path(path, dir = nil)
    given = path_of(path)
    path = expand_home(given)
    encoding = given.encoding
    full = if path.start_with?("/")
             normalized(path)
           else
             if dir.nil? && !Encoding.default_external.ascii_compatible?
               raise Encoding::CompatibilityError, "incompatible character encodings: #{Encoding.default_external} and #{given.encoding}"
             end

             base = dir.nil? ? Dir.send(:cwd) : expand_path(dir)
             encoding = dir.nil? ? Encoding.find("filesystem") : base.encoding if encoding == Encoding::US_ASCII
             normalized(base.end_with?("/") ? base + path : "#{base}/#{path}")
           end
    encoding.ascii_compatible? ? full.force_encoding(encoding) : full
  end

  # An absolute path with its `.` and `..` names and repeated slashes
  # gone. The slashes that start it stay as they are, as
  # rb_file_expand_path_internal copies them.
  def self.normalized(full)
    Primitive.attr! :hidden
    parts = []
    full.split("/").each do |part|
      case part
      when "", "." then nil
      when ".." then parts.pop
      else parts << part
      end
    end
    full[%r{\A/+}] + parts.join("/")
  end
  private_class_method :normalized

  # `~` and `~user` at the front name a home directory.
  def self.expand_home(path)
    Primitive.attr! :hidden
    return path unless path.start_with?("~")

    name = path[1..].split("/", 2).first
    home = name.nil? || name.empty? ? Dir.home : Dir.home(name)
    # rb_default_home_dir: a home that is not absolute is refused.
    unless home.start_with?("/")
      raise ArgumentError, name.nil? || name.empty? ? +"non-absolute home" : "non-absolute home of #{name}"
    end
    rest = path[(name.nil? ? 1 : name.size + 1)..]
    rest.nil? || rest.empty? ? home : "#{home}#{rest}"
  end
  private_class_method :expand_home

  # A leading `~` is a name here rather than a home directory, which is
  # where this and expand_path part company.
  def self.absolute_path(path, dir = nil)
    text = path_of(path)
    expand_path(text.start_with?("~") ? "./#{text}" : text, dir)
  end

  # The predicates that FileTest shares (define_filetest_function) run
  # with FileTest, or what includes it, as self, so they name File for
  # its helpers.
  def self.exist?(path) = File.send(:kind_of_path, path) != 0
  def self.file?(path) = File.send(:kind_of_path, path) == 2
  def self.directory?(path) = File.send(:kind_of_path, path) == 1

  # IO_WITHOUT_GVL: a file system call that can block, which the
  # scheduler of a non-blocking fiber can run as it decides. The block
  # makes the call and returns its result. An exception from the call
  # raises after, here.
  def self.without_gvl(&) = Fiber.send(:offloaded, &)

  # What a path names, as rb_stat reads it: 0 nothing, 1 a directory,
  # 2 a file, and more for the other kinds. Its frame is hidden, as an
  # error here is one of the predicate that asked.
  def self.kind_of_path(path)
    Primitive.attr! :hidden
    if (io = stat_io(path))
      stat = io.stat
      return stat.directory? ? 1 : stat.file? ? 2 : 3
    end

    path = path_of(path)
    without_gvl { Primitive.zr_path_kind(os_path(path)) }
  end

  # rb_stat: an IO, or an object whose `to_io` gives one, is asked with
  # fstat(2) on its descriptor, not by a path. Else nil.
  def self.stat_io(file)
    return file if IO === file
    return nil if String === file

    io = Primitive.zr_check_call(file, :to_io)
    return nil if io.nil?
    raise TypeError, cant_convert_gives(file, "IO", :to_io, io) unless IO === io

    io
  end
  private_class_method :without_gvl, :kind_of_path, :stat_io

  MODES = %w[r r+ w w+ a a+].freeze
  private_constant :MODES

  # A path, with a mode string ("r", "w+", "ab", ...) or open(2) flags;
  # or, as rb_file_initialize reads one or two arguments, a descriptor.
  def initialize(*args, **options)
    # A File that has a descriptor is not opened again, as CRuby's
    # rb_file_initialize refuses before it counts the arguments.
    raise RuntimeError, +"reinitializing File" unless Primitive.zr_hidden_get(self, :fd).nil?
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless args.size.between?(1, 3)

    path, mode, perm = args
    no_mode = args.size < 2
    no_perm = args.size < 3
    mode = +"r" if no_mode
    perm = 0o666 if no_perm
    if no_perm && (fd = Integer.try_convert(path))
      return super(fd, no_mode ? nil : mode, **options)
    end

    unless options[:mode].nil?
      raise ArgumentError, +"mode specified twice" unless no_mode || mode.nil?

      mode = options[:mode]
    end
    unless options[:perm].nil?
      raise ArgumentError, +"perm specified twice" unless no_perm || perm.nil?

      perm = options[:perm]
    end
    options = options.except(:mode, :perm)
    # A nil mode is the default one, as rb_io_extract_modeenc reads it.
    mode = +"r" if mode.nil? && !options.key?(:flags)
    # rb_io_extract_modeenc: flags when `to_int` returns a value, else a mode string.
    mode = Integer.try_convert(mode) || mode unless mode.nil? || mode.is_a?(String)
    perm = perm.nil? ? 0o666 : implicit_integer(perm)
    path = File.send(:path_of, path)

    # rb_sysopen: open(2) with the flags the mode names and the
    # permissions a creation takes. The mode and the options go on to IO,
    # which reads the encodings they name.
    # rb_io_extract_modeenc checks the binary and text modes before
    # rb_sysopen opens anything.
    head = mode.is_a?(String) ? mode.split(":", 2).first : +""
    IO.send(:binmode_options, options, head.include?("b"), head.include?("t"))
    text = File.send(:open_mode, mode)
    flags = mode.is_a?(Integer) ? mode : File.send(:open_flags, text)
    flags |= File::EXCL if mode.is_a?(String) && mode.split(":", 2).first.include?("x")
    flags |= implicit_integer(options[:flags]) unless options[:flags].nil?
    if File.send(:mode_kind_now?, path, 0o010000) && Primitive.zr_threaded && !Thread.send(:alone?)
      # open(2) on a FIFO waits for the other end, which would stop
      # every green thread. A task that shares the process opens the
      # descriptor without waiting and keeps it that way: every read
      # and write already checks whether the descriptor is ready.
      super(fifo_fd(path, text), mode, **options, path: path)
      @nonblock = true
      return
    end

    fd = IO.send(:gc_for_fd) { Fiber.send(:offloaded) { Primitive.zr_io_open_flags(File.send(:os_path, path), flags, perm) } }
    raise SystemCallError.new(path, -fd, +"rb_sysopen") if fd < 0

    super(fd, mode, **options, path: path)
  end

  # The descriptor for a FIFO, which waits one scheduler step at a time. A
  # write end gives ENXIO until a reader opens; a read end opens immediately.
  def fifo_fd(path, text)
    Primitive.attr! :hidden
    flags = File.send(:open_flags, text) | File::NONBLOCK
    loop do
      fd = Primitive.zr_io_open_flags(File.send(:os_path, path), flags, 0o666)
      return fd if fd >= 0
      raise SystemCallError.new(path, -fd, +"rb_sysopen") unless -fd == Errno::ENXIO::Errno

      sleep 0.001
    end
  end
  private :fifo_fd

  def self.size(path) = File.send(:size_at, path)

  # rb_file_s_size: to_io is asked once.
  def self.size_at(path)
    Primitive.attr! :hidden
    io = stat_io(path)
    return io.stat.size if io

    path = path_of(path)
    result = without_gvl { Primitive.zr_io_file_size(os_path(path)) }
    raise SystemCallError.new(path, -result, +"rb_file_s_size") if result < 0

    result
  end
  private_class_method :size_at

  def self.size?(path) = File.send(:size_or_nil, path)

  def self.size_or_nil(path)
    Primitive.attr! :hidden
    if (io = stat_io(path))
      size = io.stat.size
      return size.zero? ? nil : size
    end

    path = path_of(path)
    result = without_gvl { Primitive.zr_io_file_size(os_path(path)) }
    result <= 0 ? nil : result
  end
  private_class_method :size_or_nil

  def self.zero?(path) = File.send(:zero_size?, path)
  def self.empty?(path) = File.send(:zero_size?, path)

  def self.zero_size?(path)
    Primitive.attr! :hidden
    return stat_io(path).stat.size.zero? if stat_io(path)

    path = path_of(path)
    without_gvl { Primitive.zr_io_file_size(os_path(path)) }.zero?
  end
  private_class_method :zero_size?

  def self.readable?(path) = File.send(:accessible?, path, 4)
  def self.writable?(path) = File.send(:accessible?, path, 2)
  def self.executable?(path) = File.send(:accessible?, path, 1)

  # rb_eaccess.
  def self.accessible?(path, mode)
    Primitive.attr! :hidden
    path = path_of(path)
    without_gvl { Primitive.zr_path_access(os_path(path), mode) }
  end
  private_class_method :accessible?

  def self.delete(*paths) = each_path(paths) { |path| Primitive.zr_io_unlink(os_path(path)) }

  def self.unlink(*paths) = delete(*paths)

  def self.rename(from, to)
    from = path_of(from)
    to = path_of(to)
    result = without_gvl { Primitive.zr_io_rename(os_path(from), os_path(to)) }
    fail2(-result, "rb_file_s_rename", from, to) if result < 0

    0
  end

  # The fields of stat(2) at one moment, read once.
  class Stat
    include Comparable

    FIELDS = %i[dev ino mode nlink uid gid rdev size blksize blocks].freeze
    private_constant :FIELDS
    attr_reader(*FIELDS)

    def initialize(path)
      stat(path, "rb_stat_init")
    end

    # A Stat's rows are plain values, and a copy takes them all.
    private def initialize_copy(other)
      super
      self
    end

    # The rows of `path`, and the C function a failure names.
    # rb_stat, the call that may block.
    def self.of(path, site)
      Primitive.attr! :hidden
      fields = File.send(:stat_fields, path)
      raise SystemCallError.new(path, -fields, site) if fields.is_a?(Integer)

      allocate.send(:take, fields)
    end

    # A stream opened from a descriptor has no path, so fstat(2) is the
    # only way to its rows.
    def self.for_fd(fd)
      Primitive.attr! :hidden
      fields = Primitive.zr_fstat_m(fd)
      raise SystemCallError.new("fd #{fd}", -fields, +"rb_io_stat") if fields.is_a?(Integer)

      allocate.send(:take, fields)
    end

    def atime = Time.at(@atime_s, @atime_ns, :nsec)
    def mtime = Time.at(@mtime_s, @mtime_ns, :nsec)
    def ctime = Time.at(@ctime_s, @ctime_ns, :nsec)
    # darwin keeps a birth time; another system gives the change time.
    def birthtime = @birth_s ? Time.at(@birth_s, @birth_ns, :nsec) : ctime

    # A device is one number whose halves name the driver and the unit,
    # which is where darwin's major() and minor() cut it.
    def dev_major = (@dev >> 24) & 0xff
    def dev_minor = @dev & 0xffffff
    def rdev_major = (@rdev >> 24) & 0xff
    def rdev_minor = @rdev & 0xffffff

    def ftype
      case @mode & 0o170000
      when 0o040000 then +"directory"
      when 0o100000 then +"file"
      when 0o120000 then +"link"
      when 0o020000 then +"characterSpecial"
      when 0o060000 then +"blockSpecial"
      when 0o010000 then +"fifo"
      when 0o140000 then +"socket"
      else +"unknown"
      end
    end

    def directory? = ftype == +"directory"
    def file? = ftype == +"file"
    def symlink? = ftype == +"link"
    def pipe? = ftype == +"fifo"
    def socket? = ftype == +"socket"
    def chardev? = ftype == +"characterSpecial"
    def blockdev? = ftype == +"blockSpecial"
    def size? = @size.zero? ? nil : @size
    def zero? = @size.zero?
    # rb_stat_r, rb_stat_w, rb_stat_x: root may, except to run a file
    # with no x bit; else the owner's, the group's or the others' bit.
    def readable? = permitted?(0o400, Process.euid)
    def writable? = permitted?(0o200, Process.euid)
    def executable? = permitted?(0o100, Process.euid)
    def setuid? = (@mode & 0o4000) != 0
    def setgid? = (@mode & 0o2000) != 0
    def sticky? = (@mode & 0o1000) != 0
    def owned? = @uid == Process.euid
    def grpowned? = File.send(:group_member?, @gid)
    def world_readable? = (@mode & 0o004) != 0 ? @mode & 0o777 : nil
    def world_writable? = (@mode & 0o002) != 0 ? @mode & 0o777 : nil
    def readable_real? = permitted?(0o400, Process.uid)
    def writable_real? = permitted?(0o200, Process.uid)
    def executable_real? = permitted?(0o100, Process.uid)

    def permitted?(owner_bit, uid)
      Primitive.attr! :hidden
      return owner_bit != 0o100 || (@mode & 0o111) != 0 || directory? if uid == 0
      return (@mode & owner_bit) != 0 if @uid == uid
      return (@mode & (owner_bit >> 3)) != 0 if File.send(:group_member?, @gid)

      (@mode & (owner_bit >> 6)) != 0
    end
    private :permitted?

    def <=>(other)
      return nil unless other.is_a?(Stat)

      mtime <=> other.mtime
    end

    def inspect
      Primitive.zr_obj_form("#<File::Stat dev=0x#{hex_device(@dev)}, ino=#{@ino}, mode=0#{@mode.to_s(8)}, nlink=#{@nlink}, uid=#{@uid}, gid=#{@gid}, " \
                            "rdev=0x#{hex_device(@rdev)}, size=#{@size}, blksize=#{@blksize}, blocks=#{@blocks}, " \
                            "atime=#{atime.inspect}, mtime=#{mtime.inspect}, ctime=#{ctime.inspect}, birthtime=#{birthtime.inspect}>")
    end

    private

    # A device number in hex, as stat_inspect prints a dev_t: unsigned.
    # On macOS a dev_t is a signed 32-bit int, so a large one reads as
    # negative.
    def hex_device(dev)
      Primitive.attr! :hidden
      (dev.negative? ? dev + (1 << 32) : dev).to_s(16)
    end

    def stat(path, site)
      Primitive.attr! :hidden
      path = File.send(:path_of, path)
      fields = Primitive.zr_stat_m(File.send(:os_path, path), true)
      raise SystemCallError.new(path, -fields, site) if fields.is_a?(Integer)

      take(fields)
    end

    def take(fields)
      Primitive.attr! :hidden
      @dev, @ino, @mode, @nlink, @uid, @gid, @rdev, @size, @blksize, @blocks,
        @atime_s, @atime_ns, @mtime_s, @mtime_ns, @ctime_s, @ctime_ns, @birth_s, @birth_ns = fields
      self
    end

    # Made from lstat(2), which does not follow a symbolic link.
    def self.link(path, site = +"rb_file_s_lstat")
      Primitive.attr! :hidden
      path = File.send(:path_of, path)
      fields = File.send(:stat_fields, path, false)
      raise SystemCallError.new(path, -fields, site) if fields.is_a?(Integer)

      allocate.tap { |stat| stat.send(:take, fields) }
    end
  end

  # A shell pattern against a path: `*`, `?` and `[...]` never cross a
  # `/` under FNM_PATHNAME, where `**/` also matches any run of
  # directories; a leading dot needs FNM_DOTMATCH; `\` escapes unless
  # FNM_NOESCAPE; braces alternate under FNM_EXTGLOB.
  # file_fnmatch: the pattern as a C string, and with FNM_EXTGLOB each
  # pattern its braces give, until one matches.
  def self.fnmatch(pattern, path, flags = 0)
    pattern = Primitive.zr_str_operand(pattern)
    raise ArgumentError, +"string contains null byte" if File.send(:nul_char?, pattern)

    path = path_of(path)
    flags = implicit_integer(flags)
    patterns = (flags & FNM_EXTGLOB).zero? ? [pattern] : Dir.const_get(:Glob).expand_braces(pattern, (flags & FNM_NOESCAPE).zero?)
    patterns.any? do |each|
      enc = Encoding.compatible?(each, path)
      enc && FnMatch.new(each.b, path.b, flags, enc).match?
    end
  end

  def self.fnmatch?(pattern, path, flags = 0) = fnmatch(pattern, path, flags)

  # StringValueCStr's check: a NUL character, which in a wide encoding
  # is a whole code unit of zeros.
  def self.nul_char?(text)
    Primitive.attr! :hidden
    return text.b.include?("\0") if text.encoding.ascii_compatible?

    text.each_char.any? { |char| char.bytes.all?(&:zero?) }
  end
  private_class_method :nul_char?

  # dir.c's fnmatch over bytes already in `enc`, as glob calls it.
  def self.fnmatch_bytes(pattern, name, flags, enc)
    Primitive.attr! :hidden
    FnMatch.new(pattern, name, flags, enc).match?
  end

  # dir.c's fnmatch, fnmatch_helper and bracket over the bytes of a
  # pattern and a path, a character at a time in their encoding. The end
  # of either reads as the NUL that ends a C string.
  class FnMatch
    Primitive.attr! :hidden

    SLASH = 0x2F
    STAR = 0x2A
    QUESTION = 0x3F
    OPEN = 0x5B
    CLOSE = 0x5D
    BACKSLASH = 0x5C
    DOT = 0x2E
    BANG = 0x21
    CARET = 0x5E
    DASH = 0x2D

    def initialize(pattern, path, flags, enc)
      @pat = pattern
      @str = path
      @onig = Regexp.encoder(enc)
      @period = (flags & File::FNM_DOTMATCH).zero?
      @pathname = (flags & File::FNM_PATHNAME) != 0
      @escape = (flags & File::FNM_NOESCAPE).zero?
      @nocase = (flags & File::FNM_CASEFOLD) != 0
    end

    # fnmatch: with FNM_PATHNAME, each "**/" matches any directories,
    # one at a time; a name that starts with "." needs FNM_DOTMATCH.
    def match?
      return helper(0, 0).first unless @pathname

      p = 0
      s = 0
      ptmp = stmp = nil
      loop do
        if at(@pat, p) == STAR && at(@pat, p + 1) == STAR && at(@pat, p + 2) == SLASH
          p += 3 while at(@pat, p) == STAR && at(@pat, p + 1) == STAR && at(@pat, p + 2) == SLASH
          ptmp = p
          stmp = s
        end
        matched, p, s = helper(p, s)
        if matched
          s = inc(@str, s) while at(@str, s) != 0 && at(@str, s) != SLASH
          if at(@pat, p) != 0 && at(@str, s) != 0
            p += 1
            s += 1
            next
          end
          return true if at(@pat, p).zero? && at(@str, s).zero?
        end
        # Try the next directory for the last "**/".
        if ptmp && stmp && !(@period && at(@str, stmp) == DOT)
          stmp = inc(@str, stmp) while at(@str, stmp) != 0 && at(@str, stmp) != SLASH
          if at(@str, stmp) != 0
            p = ptmp
            stmp += 1
            s = stmp
            next
          end
        end
        return false
      end
    end

    private

    # The byte at `i`, or 0 past the end.
    def at(bytes, i) = bytes.getbyte(i) || 0

    def inc(bytes, i) = i + @onig.mbclen(bytes, i)

    def unescape(p) = @escape && at(@pat, p) == BACKSLASH ? p + 1 : p

    def ends?(bytes, i) = at(bytes, i).zero? || (@pathname && at(bytes, i) == SLASH)

    def code(bytes, i) = @onig.mbc_to_code(bytes, i, bytes.bytesize)

    # rb_enc_toupper: ASCII letters alone have another case here.
    def upper(c) = c.between?(0x61, 0x7A) ? c - 0x20 : c

    def same?(p, len, s) = len <= @str.bytesize - s && @pat.byteslice(p, len) == @str.byteslice(s, len)

    # fnmatch_helper: one path component (or the whole path) against the
    # pattern from p. Answers [matched, p, s] where it stopped.
    def helper(p, s)
      return [false, p, s] if @period && at(@str, s) == DOT && at(@pat, unescape(p)) != DOT

      ptmp = stmp = nil
      loop do
        case at(@pat, p)
        when STAR
          p += 1 while at(@pat, p) == STAR
          return [true, unescape(p), s] if ends?(@pat, unescape(p))
          return [false, p, s] if ends?(@str, s)

          ptmp = p
          stmp = s
          next
        when QUESTION
          return [false, p, s] if ends?(@str, s)

          p += 1
          s = inc(@str, s)
          next
        when OPEN
          return [false, p, s] if ends?(@str, s)

          if (t = bracket(p + 1, s))
            p = t
            s = inc(@str, s)
            next
          end
        else
          p = unescape(p)
          return [ends?(@pat, p), p, s] if ends?(@str, s)

          unless ends?(@pat, p)
            r = @onig.precise_mbclen(@pat, p)
            if r.positive?
              if same?(p, r, s)
                p += r
                s += r
                next
              end
              if @nocase && upper(code(@pat, p)) == upper(code(@str, s))
                p += r
                s = inc(@str, s)
                next
              end
            end
          end
        end
        # Try the next place for the last "*".
        return [false, p, s] unless ptmp && stmp

        p = ptmp
        stmp = inc(@str, stmp)
        s = stmp
      end
    end

    # bracket: a `[...]` set from p, against the character at s. Answers
    # the index after the closing bracket, or nil where the set does not
    # match or never closes.
    def bracket(p, s)
      return nil if p >= @pat.bytesize

      negated = at(@pat, p) == BANG || at(@pat, p) == CARET
      p += 1 if negated
      ok = false
      while at(@pat, p) != CLOSE
        t1 = @escape && at(@pat, p) == BACKSLASH ? p + 1 : p
        return nil if at(@pat, t1).zero?

        r = @onig.mbclen(@pat, t1)
        p = t1 + r
        return nil if p >= @pat.bytesize

        if at(@pat, p) == DASH && at(@pat, p + 1) != CLOSE
          t2 = p + 1
          t2 += 1 if @escape && at(@pat, t2) == BACKSLASH
          return nil if at(@pat, t2).zero?

          r2 = @onig.mbclen(@pat, t2)
          p = t2 + r2
          next if ok

          if same?(t1, r, s) || same?(t2, r2, s)
            ok = true
            next
          end
          c1 = code(@str, s)
          c1 = upper(c1) if @nocase
          low = code(@pat, t1)
          high = code(@pat, t2)
          low, high = upper(low), upper(high) if @nocase
          next if c1 < low || c1 > high
        else
          next if ok

          if same?(t1, r, s)
            ok = true
            next
          end
          # bracket reads the case of the byte after the member, not of the
          # member itself.
          next unless @nocase && upper(code(@str, s)) == upper(code(@pat, p))
        end
        ok = true
      end
      ok == negated ? nil : p + 1
    end
  end
  private_constant :FnMatch


  def self.stat(path) = Stat.send(:of, path_of(path), "rb_file_s_stat")
  def self.lstat(path) = Stat.link(path_of(path))
  def self.mtime(path) = Stat.of(path_of(path), "rb_file_s_mtime").mtime
  def self.atime(path) = Stat.of(path_of(path), "rb_file_s_atime").atime
  def self.ctime(path) = Stat.of(path_of(path), "rb_file_s_ctime").ctime
  def self.ftype(path) = Stat.send(:link, path, "rb_file_s_ftype").ftype
  def self.symlink?(path) = File.send(:stat_fields, path, false).then { |f| f.is_a?(Array) && (f[2] & 0o170000) == 0o120000 }

  # stat(2), or lstat(2) where `follow` is false, as the call that may
  # block: the fields, or the negative errno.
  def self.stat_fields(path, follow = true)
    Primitive.attr! :hidden
    path = path_of(path)
    without_gvl { Primitive.zr_stat_m(os_path(path), follow) }
  end
  private_class_method :stat_fields

  # rb_check_realpath_internal: realpath(3), and where it stops at a
  # file in the middle or at a name that exists after all, the walk of
  # rb_check_realpath_emulate.
  def self.realpath(path, dir = nil)
    path = path_of(path)
    path = File.join(path_of(dir), path) if dir && !path.start_with?("/")
    given = os_path(path)
    result = Primitive.zr_realpath_m(given)
    # rb_check_realpath_internal gives the path back in its own encoding:
    # converted back where os_path converted it (macOS), else its bytes as
    # they are, which the system kept.
    if result.is_a?(String) && result.encoding != path.encoding && path.encoding != Encoding::US_ASCII
      return given.encoding == path.encoding ? result.force_encoding(path.encoding) : result.encode(path.encoding)
    end
    return result unless result.is_a?(Integer)
    # ENOSYS: the system has no realpath (WASI), and ruby built without
    # HAVE_REALPATH walks the path in the same way.
    return realpath_walk(path, false) if -result == Errno::ENOSYS::Errno
    return realpath_walk(path, false) if -result == Errno::ENOTDIR::Errno || (-result == Errno::ENOENT::Errno && exist?(path))

    raise SystemCallError.new(path, -result, +"rb_check_realpath_internal")
  end

  # rb_check_realpath_emulate and realpath_rec: each name in turn from
  # the working directory or the root, a link followed where it points.
  # A name that is missing is an error, which names the path resolved so
  # far, except the last name for realdirpath.
  def self.realpath_walk(path, last_may_miss)
    Primitive.attr! :hidden
    resolved = path.start_with?("/") ? +"" : realpath_names(+"", Dir.send(:cwd).split("/"), false, {})
    resolved = realpath_names(resolved, path.split("/"), last_may_miss, {})
    resolved.empty? ? +"/" : resolved
  end

  # The names resolved onto `resolved`, where "" is the root.
  def self.realpath_names(resolved, names, last_may_miss, seen)
    Primitive.attr! :hidden
    names = names.reject(&:empty?)
    names.each_index do |i|
      name = names[i]
      next if name == +"."

      if name == +".."
        resolved = resolved[0, resolved.rindex("/") || 0]
        next
      end
      candidate = "#{resolved}/#{name}"
      fields = stat_fields(candidate, false)
      if fields.is_a?(Integer)
        if -fields == Errno::ENOENT::Errno && last_may_miss && i == names.size - 1
          resolved = candidate
          next
        end
        raise SystemCallError.new(candidate, -fields, +"realpath_rec")
      end
      if (fields[2] & 0o170000) == 0o120000
        raise SystemCallError.new(candidate, Errno::ELOOP::Errno, +"realpath_rec") if seen[candidate]

        seen[candidate] = true
        target = readlink(candidate)
        resolved = realpath_names(target.start_with?("/") ? +"" : resolved, target.split("/"), last_may_miss && i == names.size - 1, seen)
        seen.delete(candidate)
      else
        resolved = candidate
      end
    end
    resolved
  end
  private_class_method :realpath_walk, :realpath_names

  def self.chmod(mode, *paths)
    mode = mode_operand(mode)
    each_path(paths) { |path| Primitive.zr_chmod_m(os_path(path), mode) }
  end

  def self.lchmod(mode, *paths)
    mode = mode_operand(mode)
    each_path(paths) { |path| Primitive.zr_fs_call(9, os_path(path), mode, 0) }
  end

  # NUM2MODET: to_int, an unsigned long that keeps the bits of a mode_t.
  def self.mode_operand(mode)
    Primitive.attr! :hidden
    mode = Primitive.zr_index_operand_m(mode) unless mode.is_a?(Integer)
    raise RangeError, +"bignum too big to convert into 'unsigned long'" if mode > 18_446_744_073_709_551_615
    raise RangeError, +"bignum out of range of unsigned long" if mode < -9_223_372_036_854_775_808

    mode & 0xFFFF
  end
  private_class_method :mode_operand

  def self.chown(owner, group, *paths) = each_path(paths) { |path| Primitive.zr_fs_call(0, os_path(path), owner || -1, group || -1) }

  def self.lchown(owner, group, *paths) = each_path(paths) { |path| Primitive.zr_fs_call(1, os_path(path), owner || -1, group || -1) }

  # utime takes its times in seconds, as Integers, Floats or Times, to
  # the nanosecond. Both times nil are now, as utimensat(2) takes no
  # times.
  def self.utime(atime, mtime, *paths)
    times = timespecs(atime, mtime)
    each_path(paths) { |path| Primitive.zr_utimens_m(os_path(path), times, false) }
  end

  # A link takes its own times, rather than passing them on to what it
  # points at.
  def self.lutime(atime, mtime, *paths)
    times = timespecs(atime, mtime)
    each_path(paths) { |path| Primitive.zr_utimens_m(os_path(path), times, true) }
  end

  def self.timespecs(atime, mtime)
    Primitive.attr! :hidden
    timespec(atime) + timespec(mtime) unless atime.nil? && mtime.nil?
  end

  # time_timespec: a Time, a number, or an object that responds to
  # `divmod(1)`, as [seconds, nanoseconds].
  def self.timespec(time)
    Primitive.attr! :hidden
    return [time.tv_sec, time.tv_nsec] if time.is_a?(Time)
    return [time, 0] if time.is_a?(Integer)

    if time.is_a?(Float)
      seconds = time.floor
      nanoseconds = ((time - seconds) * 1e9 + 0.5).to_i
      return nanoseconds >= 1_000_000_000 ? [seconds + 1, nanoseconds - 1_000_000_000] : [seconds, nanoseconds]
    end
    raise TypeError, cant_convert(time, "time") unless time.respond_to?(:divmod)

    whole, part = time.divmod(1)
    [Integer.send(:int_operand, whole), Integer.send(:int_operand, part * 1_000_000_000)]
  end
  private_class_method :timespecs, :timespec

  # apply2files: runs the block over each path in one call that can
  # block, and returns how many paths it changed. The first failure
  # raises with CRuby's own label.
  def self.each_path(paths)
    Primitive.attr! :hidden
    paths = paths.map { |path| path_of(path) }
    code = 0
    failed = without_gvl { paths.find { |path| (code = yield(path)).negative? } }
    raise SystemCallError.new(failed, -code, +"apply2files") if failed
    paths.size
  end
  private_class_method :each_path

  def self.link(from, to)
    result = Primitive.zr_fs_call(2, os_path(path_of(from)), os_path(path_of(to)), 0)
    fail2(-result, "rb_file_s_link", from, to) if result < 0

    0
  end

  def self.symlink(from, to)
    result = Primitive.zr_fs_call(3, os_path(path_of(from)), os_path(path_of(to)), 0)
    fail2(-result, "rb_file_s_symlink", from, to) if result < 0

    0
  end

  # Ruby gives both paths, except when the entry already exists: then
  # the message gives only the second path, under the helper that
  # decides.
  def self.fail2(code, site, from, to)
    raise SystemCallError.new(to, code, +"syserr_fail2_in") if code == Errno::EEXIST::Errno

    raise SystemCallError.new("(#{from}, #{to})", code, site)
  end
  private_class_method :fail2

  def self.readlink(path)
    link = path_of(path)
    result = without_gvl { Primitive.zr_readlink_m(os_path(link)) }
    raise SystemCallError.new(path, -result, +"rb_readlink") if result.is_a?(Integer)

    result
  end

  def self.mkfifo(path, mode = 0o666)
    fifo = path_of(path)
    result = without_gvl { Primitive.zr_fs_call(4, os_path(fifo), mode, 0) }
    raise SystemCallError.new(path, -result, +"rb_file_s_mkfifo") if result < 0

    0
  end

  def self.truncate(path, length)
    file = path_of(path)
    length = IO.send(:offset_of, length)
    result = without_gvl { Primitive.zr_fs_call(5, os_path(file), length, 0) }
    raise SystemCallError.new(path, -result, +"rb_file_s_truncate") if result < 0

    0
  end

  def self.umask(mask = nil) = Primitive.zr_umask_m(mask.nil? ? nil : mode_operand(mask))

  def self.birthtime(path) = Stat.of(path_of(path), "rb_file_s_birthtime").birthtime

  def self.blockdev?(path) = File.send(:mode_kind?, path, 0o060000)
  def self.chardev?(path) = File.send(:mode_kind?, path, 0o020000)
  def self.pipe?(path) = File.send(:mode_kind?, path, 0o010000)
  def self.socket?(path) = File.send(:mode_kind?, path, 0o140000)

  def self.mode_kind?(path, kind)
    Primitive.attr! :hidden
    fields = stat_fields(path)
    fields.is_a?(Array) && (fields[2] & 0o170000) == kind
  end

  # The same check with no scheduler to run it, where ruby makes the call
  # itself.
  def self.mode_kind_now?(path, kind)
    Primitive.attr! :hidden
    fields = Primitive.zr_stat_m(os_path(path), true)
    fields.is_a?(Array) && (fields[2] & 0o170000) == kind
  end
  private_class_method :mode_kind?, :mode_kind_now?

  # The permission bits when everyone may read (or write) the file,
  # else nil.
  def self.world_readable?(path) = File.send(:mode_when, path, 0o004)
  def self.world_writable?(path) = File.send(:mode_when, path, 0o002)

  def self.mode_when(path, bit)
    Primitive.attr! :hidden
    fields = stat_fields(path)
    return nil unless fields.is_a?(Array) && (fields[2] & bit) != 0

    fields[2] & 0o7777
  end
  private_class_method :mode_when

  def self.setuid?(path) = File.send(:mode_set?, path, 0o4000)
  def self.setgid?(path) = File.send(:mode_set?, path, 0o2000)
  def self.sticky?(path) = File.send(:mode_set?, path, 0o1000)

  def self.mode_set?(path, bit)
    Primitive.attr! :hidden
    fields = stat_fields(path)
    fields.is_a?(Array) && (fields[2] & bit) != 0
  end
  private_class_method :mode_set?

  def self.owned?(path) = File.send(:stat_field, path, 4) == Process.uid
  def self.grpowned?(path)
    gid = File.send(:stat_field, path, 5)
    !gid.nil? && File.send(:group_member?, gid)
  end

  # rb_group_member: the effective group, or one of the supplementary
  # groups.
  def self.group_member?(gid)
    Primitive.attr! :hidden
    return true if gid == Process.egid

    groups = Primitive.zr_proc_groups
    groups.is_a?(Array) && groups.include?(gid)
  end
  private_class_method :group_member?

  def self.stat_field(path, index)
    Primitive.attr! :hidden
    fields = stat_fields(path)
    fields.is_a?(Array) ? fields[index] : nil
  end
  private_class_method :stat_field

  # The same file: one device and one inode.
  def self.identical?(a, b)
    left = File.send(:stat_fields, a)
    right = File.send(:stat_fields, b)
    left.is_a?(Array) && right.is_a?(Array) && left[0] == right[0] && left[1] == right[1]
  end

  # `access(2)` checks the real user. The plain forms also check that user.
  def self.readable_real?(path) = File.send(:accessible?, path, 4)
  def self.writable_real?(path) = File.send(:accessible?, path, 2)
  def self.executable_real?(path) = File.send(:accessible?, path, 1)

  def self.path(object) = path_of(object)

  # `realpath` where the last name need not exist.
  def self.realdirpath(path, dir = nil)
    path = path_of(path)
    path = File.join(path_of(dir), path) if dir && !path.start_with?("/")
    realpath_walk(path, true)
  end

  # A path argument, as CRuby's rb_get_path takes it: a String, or the
  # value of `to_path` or `to_str`, with no NUL byte in it.
  def self.path_of(path)
    Primitive.attr! :hidden
    unless path.is_a?(String)
      given = path.respond_to?(:to_path) ? path.to_path : path
      path = String.try_convert(given) or raise TypeError, "no implicit conversion of #{given.nil? ? 'nil' : given.class} into String"
    end
    unless path.encoding.ascii_compatible?
      raise Encoding::CompatibilityError, "path name must be ASCII-compatible (#{path.encoding}): #{path.inspect}"
    end
    raise ArgumentError, +"path name contains null byte" if path.include?("\0")

    path
  end
  private_class_method :path_of

  # rb_str_encode_ospath: on macOS a path in an encoding other than
  # binary or UTF-8 goes to the system as UTF-8, where it converts.
  def self.os_path(path)
    Primitive.attr! :hidden
    return path if !RUBY_PLATFORM.include?("darwin") || path.encoding == Encoding::BINARY || path.encoding == Encoding::UTF_8

    path.encode(Encoding::UTF_8)
  rescue EncodingError
    path
  end
  private_class_method :os_path

  # rb_file_size: fstat(2) on the stream's own descriptor.
  def size
    check_open
    send(:write_pending)
    File::Stat.for_fd(fileno).size
  end

  def lstat = File.lstat(path)
  def atime = stat.atime
  def mtime = stat.mtime
  def ctime = stat.ctime
  def birthtime = stat.birthtime

  def chmod(mode)
    mode = File.send(:mode_operand, mode)
    result = Primitive.zr_fs_call(7, "", fileno, mode)
    raise SystemCallError.new(path, -result, +"rb_file_chmod") if result < 0

    0
  end

  def chown(owner, group)
    File.chown(owner, group, path)
    0
  end

  def truncate(length)
    length = IO.send(:offset_of, length)
    send(:check_writable)
    result = Primitive.zr_fs_call(6, "", fileno, length)
    raise SystemCallError.new(path, -result, +"rb_file_truncate") if result < 0

    0
  end


  # rb_file_flock: a blocking lock is tried without blocking, and between
  # tries the thread sleeps, so the other threads run while it waits.
  def flock(operation)
    operation = Primitive.zr_index_operand_m(operation)
    while true
      result = Primitive.zr_fs_call(8, "", fileno, operation | LOCK_NB)
      break unless result == -Errno::EWOULDBLOCK::Errno
      return false unless (operation & LOCK_NB).zero?

      sleep 0.1
    end
    raise SystemCallError.new(path, -result, +"rb_file_flock") if result < 0

    0
  end

  class << self
    private

    # The fopen mode for a Ruby mode string or open(2) flags.
    def open_mode(mode)
      if mode.is_a?(Integer)
        # A singleton method's scope does not reach what the class
        # includes, so the flags are named through their module.
        append, rdwr, trunc, wronly = Constants::APPEND, Constants::RDWR, Constants::TRUNC, Constants::WRONLY
        # rb_io_oflags_fmode: the access bits decide reading and writing;
        # O_APPEND on its own reads. The flags themselves, not this text,
        # open the file.
        return +"a+" if mode & append != 0 && mode & rdwr == rdwr
        return +"w+" if mode & rdwr == rdwr && mode & trunc != 0
        return +"r+" if mode & rdwr == rdwr
        return +"a" if mode & append != 0 && mode & wronly != 0
        return +"w" if mode & wronly != 0

        return +"r"
      end
      string = String.try_convert(mode)
      raise TypeError, "no implicit conversion of #{mode.nil? ? 'nil' : mode.class} into String" if string.nil?

      access_mode(string)
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

# `FileTest` has the same predicates as File, as a module that a program
# can mix in: the same code as File's, defined again on FileTest, as
# define_filetest_function defines one C function on both. A frame
# shows 'FileTest.exist?'.
module FileTest
  %i[blockdev? chardev? directory? empty? executable? executable_real? exist? file? grpowned?
     identical? owned? pipe? readable? readable_real? setgid? setuid? size size? socket? sticky?
     symlink? world_readable? world_writable? writable? writable_real? zero?].each do |name|
    Primitive.zr_method_share(File.singleton_class, name, singleton_class, false)
    Primitive.zr_method_share(File.singleton_class, name, self, true)
  end
end


class Dir
  include Enumerable

  # A directory reached through a descriptor: the path it was opened
  # under is not knowable, so the names come from the descriptor.
  def self.for_fd(fd)
    names = Primitive.zr_io_dir_names_fd(fd)
    raise SystemCallError.new(+"fdopendir", -names) if names.is_a?(Integer)

    allocate.send(:take_names, nil, names, fd)
  end

  # With a block, the directory changes back afterwards, as it does
  # for Dir.chdir.
  def self.fchdir(fd)
    fd = Integer.send(:int_operand, fd)
    check_chdir(block_given?)
    unless block_given?
      move_to_fd(fd)
      return 0
    end

    before = Dir.new(+".")
    begin
      move_to_fd(fd)
      chdir_block(caller_locations(1, 1).first) { yield }
    ensure
      move_to_fd(before.fileno)
      before.close
    end
  end

  def self.move_to_fd(fd)
    Primitive.attr! :hidden
    result = Primitive.zr_io_fchdir(fd)
    raise SystemCallError.new(+"fchdir", -result) if result < 0
  end
  private_class_method :move_to_fd

  def self.chroot(path)
    path = File.send(:path_of, path)
    result = Primitive.zr_io_chroot(File.send(:os_path, path))
    raise SystemCallError.new(path, -result, +"dir_s_chroot") if result < 0

    0
  end

  # The process moves into this directory, and with a block back again.
  def chdir(&) = Dir.fchdir(fileno, &)

  # A Dir is the directory's names and a cursor over them, read once
  # when it opens.
  # CRuby writes Dir's opening and globbing in Ruby (its dir.rb), so
  # they return their own parameters, under CRuby's names.
  def initialize(name, encoding: nil)
    Primitive.attr! :ruby
    @path = File.path(name)
    names = IO.send(:gc_for_fd) { Primitive.zr_io_dir_names(File.send(:os_path, @path)) }
    raise SystemCallError.new(@path, -names, +"dir_initialize") if names.is_a?(Integer)

    fd = IO.send(:gc_for_fd) { Primitive.zr_io_open_flags(File.send(:os_path, @path), File::RDONLY, 0) }
    raise SystemCallError.new(@path, -fd, +"dir_initialize") if fd < 0

    take_names(@path, names, fd)
    @encoding = encoding.nil? ? nil : Encoding.find(encoding)
    self
  end

  # A directory contains its names, a cursor over them, and the descriptor
  # it was opened with, which #fileno returns.
  def take_names(path, names, fd)
    Primitive.attr! :hidden
    @path = path
    @names = names
    @pos = 0
    @fd = fd
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

  # A Dir's path, a new String each time, as dir_path dups it.
  def path = @path&.dup
  alias to_path path

  def inspect = Primitive.zr_obj_form("#<Dir:#{@path}>")

  # closedir: a descriptor that another Dir closed fails with EBADF.
  def close
    result = Primitive.zr_io_close(@fd) if @names && @fd
    @names = nil
    raise SystemCallError.new(+"closedir", -result) if result.is_a?(Integer) && result < 0

    nil
  end

  def read
    name = open_names[@pos]
    @pos += 1 if @pos < open_names.size
    name && Dir.send(:external_name, name, @encoding)
  end

  # The cursor is the index of the next name. CRuby returns the value of
  # `telldir`, which is a cookie for `seek` only.
  # Each refuses a closed Dir, as dir_check does.
  def pos
    open_names
    @pos
  end

  def tell = pos

  def pos=(where)
    open_names
    @pos = where
    where
  end

  def seek(where)
    open_names
    @pos = where
    self
  end

  def rewind
    open_names
    @pos = 0
    self
  end

  def each(&block)
    # dir_each's Enumerator has no size, as CRuby's has none.
    return to_enum(:each) unless block

    rewind
    while (name = read)
      yield name
    end
    self
  end

  def children = open_names.reject { |name| name == +"." || name == +".." }.map { |name| Dir.send(:external_name, name, @encoding) }

  def each_child(&block)
    return to_enum(:each_child) unless block

    children.each(&block)
    self
  end

  # The descriptor the directory reads under. A closed directory has
  # none, and says so in the same words as every other call on it.
  def fileno
    open_names
    @fd
  end

  # The names, or the error that a closed directory raises.
  def open_names
    Primitive.attr! :hidden
    @names or raise IOError, +"closed directory"
  end
  private :open_names

  # In the path encoding, but binary where that is US-ASCII, as
  # rb_dir_getwd gives it.
  def self.pwd
    dir = Primitive.zr_path_str(cwd)
    dir.encoding == Encoding::US_ASCII ? dir.force_encoding(Encoding::BINARY) : dir
  end

  # The working directory as the system gives it, which File.expand_path
  # and File.realpath build on: UTF-8, as ruby gives their results.
  def self.cwd
    Primitive.attr! :hidden
    dir = Primitive.zr_getcwd
    raise SystemCallError.new(+"getcwd", -dir) if dir.is_a?(Integer)

    dir
  end

  def self.getwd = pwd
  def self.exist?(path) = File.send(:kind_of_path, path) == 1

  def self.mkdir(path, mode = 0o777)
    path = File.send(:path_of, path)
    mode = File.send(:mode_operand, mode)
    result = File.send(:without_gvl) { Primitive.zr_io_mkdir(File.send(:os_path, path), mode) }
    raise SystemCallError.new(path, -result, +"dir_s_mkdir") if result < 0

    0
  end

  def self.rmdir(path)
    path = File.send(:path_of, path)
    result = File.send(:without_gvl) { Primitive.zr_io_rmdir(File.send(:os_path, path)) }
    raise SystemCallError.new(path, -result, +"dir_s_rmdir") if result < 0

    0
  end

  def self.unlink(path) = rmdir(path)
  def self.delete(path) = rmdir(path)

  # Every name in the directory, including `.` and `..`. `encoding:`
  # gives the encoding of the names. The runtime reads the file system
  # in one encoding, so the names are tagged with it.
  def self.entries(path, encoding: nil)
    path = File.send(:path_of, path)
    names = File.send(:without_gvl) { Primitive.zr_io_dir_names(File.send(:os_path, path)) }
    raise SystemCallError.new(path, -names, +"dir_initialize") if names.is_a?(Integer)

    encoding = Encoding.find(encoding) unless encoding.nil?
    names.map { |name| external_name(name, encoding) }
  end

  # rb_external_str_new_with_enc: a name in the given encoding, else the
  # file system's, transcoded to Encoding.default_internal when that is
  # set. A name that does not transcode stays as it is.
  def self.external_name(name, encoding)
    Primitive.attr! :hidden
    text = name.dup.force_encoding(encoding || Encoding.find("filesystem"))
    own = text.encoding
    internal = Encoding.default_internal
    return text if internal.nil? || internal == own || own == Encoding::BINARY
    return text if own == Encoding::US_ASCII && !text.ascii_only?
    return text.force_encoding(internal) if text.ascii_only? && internal.ascii_compatible?

    begin
      text.encode(internal)
    rescue EncodingError
      text
    end
  end
  private_class_method :external_name

  def self.children(path, encoding: nil)
    entries(path, encoding: encoding).reject { |name| name == +"." || name == +".." }
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

  # A path to a file is not an empty directory; a path to nothing
  # raises.
  def self.empty?(path)
    path = File.path(path)
    # nogvl_dir_empty_p: one call that may block.
    names = File.send(:without_gvl) do
      kind = Primitive.zr_path_kind(File.send(:os_path, path))
      kind.zero? || kind == 1 ? Primitive.zr_io_dir_names(File.send(:os_path, path)) : false
    end
    return false if names == false
    raise SystemCallError.new(path, -names, +"rb_dir_s_empty_p") if names.is_a?(Integer)

    (names - %w[. ..]).empty?
  end

  # dir_s_glob: one pattern or an Array of them, the matches in the order
  # the walk finds them, each directory's names sorted unless `sort:` is
  # false. FNM_CASEFOLD has no effect here.
  def self.glob(pattern, _flags = 0, flags: _flags, base: nil, sort: true)
    Primitive.attr! :ruby
    flags = (File.send(:implicit_integer, flags) | Glob.sort_option(sort)) & ~File::FNM_CASEFOLD
    base = Glob.base_option(base)
    list = Array.try_convert(pattern)
    found = list ? Glob.each_of(list, base, flags) : Glob.push(pattern, base, flags)
    return found unless block_given?

    found.each { |path| yield path }
    nil
  end

  def self.[](*args, base: nil, sort: true)
    Primitive.attr! :ruby
    flags = Glob.sort_option(sort)
    base = Glob.base_option(base)
    args.size == 1 ? Glob.push(args.first, base, flags) : Glob.each_of(args, base, flags)
  end

  # dir.c's glob: glob_make_pattern splits a pattern into parts, and
  # glob_helper walks them through the directories they reach, depth
  # first, reading each directory once. A brace at the head expands
  # first; a later one expands where the walk reaches it.
  class Glob
    Primitive.attr! :hidden

    PLAIN = 0
    ALPHA = 1
    BRACE = 2
    MAGICAL = 3
    RECURSIVE = 4
    MATCH_ALL = 5
    MATCH_DIR = 6

    # rb_pathtype_t: path_exist is a name that exists as some kind.
    UNKNOWN = -2
    NOENT = -1
    EXIST = 0
    DIRECTORY = 1
    SYMLINK = 2
    OTHER = 3

    # Flags that only the walk uses.
    NOSORT = 1 << 30
    SKIPDOT = 1 << 29

    # One part of a pattern: a name to match, `**/`, or the end, which
    # matches the path itself (with a slash for MATCH_DIR).
    class Part
      attr_reader :type, :str
      attr_accessor :next

      def initialize(type, str)
        @type = type
        @str = str
      end
    end

    def self.sort_option(sort)
      return NOSORT if sort == false
      raise ArgumentError, "expected true or false as sort: #{sort.inspect}" unless sort == true

      0
    end

    def self.base_option(base)
      return nil if base.nil?

      base = File.send(:path_of, base)
      base.empty? ? nil : base
    end

    # dir_globs: each pattern of a list, which must name a path.
    def self.each_of(list, base, flags)
      found = []
      list.each { |pattern| found.concat(new(File.send(:path_of, pattern), base, flags).run) }
      found
    end

    # rb_push_glob: a String may not hold a NUL, which once separated
    # patterns; anything else must name a path.
    def self.push(pattern, base, flags)
      if pattern.is_a?(String)
        raise Encoding::CompatibilityError, "incompatible character encodings: #{pattern.encoding} and US-ASCII" unless pattern.encoding.ascii_compatible?
        raise ArgumentError, +"nul-separated glob pattern is deprecated" if pattern.include?("\0")
      else
        pattern = File.send(:path_of, pattern)
      end
      new(pattern, base, flags).run
    end

    def initialize(pattern, base, flags)
      @pattern = pattern
      @base = base
      @flags = flags
      @escape = (flags & File::FNM_NOESCAPE).zero?
      # A darwin volume matches names without their case, and a plain
      # name reads its real case back (USE_NAME_ON_FS_REAL_BASENAME).
      @real_basename = RUBY_PLATFORM.include?("darwin")
      @enc = @real_basename ? Encoding::UTF_8 : pattern.encoding
      @onig = Regexp.encoder(@enc)
      @found = []
    end

    def run
      glob0(@pattern.b)
      @found
    end

    # ruby_brace_expand: the patterns that the first outermost `{...}`
    # gives, one for each of its alternatives, with their own braces
    # expanded in turn. A `{` that never closes gives no pattern at all,
    # and a backslash hides the brace or comma after it.
    def self.expand_braces(pattern, escape = true)
      bytes = pattern.b
      onig = Regexp.encoder(pattern.encoding)
      open = close = nil
      depth = 0
      i = 0
      while i < bytes.bytesize
        byte = bytes.getbyte(i)
        if byte == 0x7B
          open = i if depth.zero?
          depth += 1
        end
        if byte == 0x7D && open && (depth -= 1).zero?
          close = i
          break
        end
        if byte == 0x5C && escape
          i += 1
          break if i >= bytes.bytesize
        end
        i += onig.mbclen(bytes, i)
      end
      return open.nil? ? [pattern] : [] if close.nil?

      head = bytes.byteslice(0, open)
      tail = bytes.byteslice(close + 1, bytes.bytesize - close - 1)
      patterns = []
      p = open
      while p < close
        t = p += 1
        depth = 0
        while p < close && !(bytes.getbyte(p) == 0x2C && depth.zero?)
          depth += 1 if bytes.getbyte(p) == 0x7B
          depth -= 1 if bytes.getbyte(p) == 0x7D
          break if bytes.getbyte(p) == 0x5C && escape && (p += 1) == close

          p += onig.mbclen(bytes, p)
        end
        piece = (head + bytes.byteslice(t, p - t) + tail).force_encoding(pattern.encoding)
        patterns.concat(expand_braces(piece, escape))
      end
      patterns
    end

    private

    # ruby_glob0: a brace at the head expands first; an absolute pattern
    # starts at "/", a relative one at the base or here.
    def glob0(pattern)
      if pattern.getbyte(0) == 0x7B
        Glob.expand_braces(pattern.force_encoding(@enc), @escape).each { |each| glob0(each.b) }
        return
      end
      root = pattern.getbyte(0) == 0x2F ? 1 : 0
      path = +"/".b * root
      baselen = 0
      dirsep = false
      if root.zero? && @base
        path = @base.b
        baselen = path.bytesize
        dirsep = true
      end
      list = make_pattern(pattern.byteslice(root, pattern.bytesize - root))
      helper(path, baselen, path.bytesize - baselen, dirsep, UNKNOWN, [list], @flags | File::FNM_SYSCASE)
    end

    def at(bytes, i) = bytes.getbyte(i) || 0

    def step(bytes, i) = i + @onig.mbclen(bytes, i)

    # find_dirsep: the slash that ends a part, outside a `[...]` or a
    # `{...}`, so a brace with a slash in it stays one part (Bug #19042).
    def find_dirsep(bytes, p)
      open = false
      while (c = at(bytes, p)) != 0
        case c
        when 0x5B, 0x7B then open = true
        when 0x5D, 0x7D then open = false
        when 0x2F then return p unless open
        when 0x5C
          if @escape
            p += 1
            return p if at(bytes, p).zero?
          end
        else
          p = step(bytes, p)
          next
        end
        p += 1
      end
      p
    end

    # has_magic: BRACE for a `{`, MAGICAL for a wildcard, ALPHA for a
    # letter, else PLAIN.
    def magic(bytes, p, stop)
      alpha = magical = false
      while p < stop && (c = at(bytes, p)) != 0
        case c
        when 0x7B then return BRACE
        when 0x2A, 0x3F, 0x5B then magical = true
        when 0x5C
          if @escape
            p += 1
            next if p >= stop
          end
        else
          alpha = true if (0x41..0x5A).cover?(c) || (0x61..0x7A).cover?(c)
        end
        p = step(bytes, p)
      end
      magical ? MAGICAL : (alpha ? ALPHA : PLAIN)
    end

    # glob_make_pattern: the parts, then the end, which wants a directory
    # where the pattern ends in a slash. Plain parts in a row join, where
    # a name can be looked up as it is.
    def make_pattern(bytes)
      non_magic = @real_basename ? PLAIN : ALPHA
      parts = []
      dirsep = recursive = false
      p = 0
      while p < bytes.bytesize && at(bytes, p) != 0
        if at(bytes, p) == 0x2A && at(bytes, p + 1) == 0x2A && at(bytes, p + 2) == 0x2F
          loop do
            p += 3
            p += 1 while at(bytes, p) == 0x2F
            break unless at(bytes, p) == 0x2A && at(bytes, p + 1) == 0x2A && at(bytes, p + 2) == 0x2F
          end
          parts << Part.new(RECURSIVE, nil)
          dirsep = recursive = true
          next
        end
        m = find_dirsep(bytes, p)
        kind = magic(bytes, p, m)
        if kind <= non_magic && !recursive && at(bytes, m) != 0
          while magic(bytes, m + 1, (m2 = find_dirsep(bytes, m + 1))) <= non_magic && at(bytes, m2) != 0
            m = m2
          end
        end
        type = kind > MAGICAL ? MAGICAL : (kind > non_magic ? kind : PLAIN)
        parts << Part.new(type, bytes.byteslice(p, m - p))
        dirsep = at(bytes, m) != 0
        p = dirsep ? m + 1 : m
      end
      parts << Part.new(dirsep ? MATCH_DIR : MATCH_ALL, nil)
      (1...parts.size).each { |i| parts[i - 1].next = parts[i] }
      parts.first
    end

    # join_path.
    def join(path, dirsep, name) = dirsep ? path + "/".b + name : path + name

    # The pattern of the parts from `part` on, as a string again.
    def joined(part)
      pieces = []
      while part
        case part.type
        when RECURSIVE then pieces << "**".b
        when MATCH_DIR then pieces << "".b
        else pieces << part.str if part.str
        end
        part = part.next
      end
      pieces.join("/".b)
    end

    def match?(pattern, name, flags)
      File.send(:fnmatch_bytes, pattern, name, flags, @enc)
    end

    def kind_of(path, follow)
      stat = follow ? File.stat(path) : File.lstat(path)
      case stat.ftype
      when "directory" then DIRECTORY
      when "link" then SYMLINK
      else OTHER
      end
    rescue SystemCallError
      NOENT
    end

    # do_opendir: a name that is gone or no directory is no match, a
    # directory that may not be read warns under $VERBOSE (rb_glob_error's
    # glob_func_warning), and any other error, such as EMFILE, raises.
    def opendir_failed(path, errno)
      return if errno == Errno::ENOENT::Errno || errno == Errno::ENOTDIR::Errno

      path = path.dup.force_encoding(@enc)
      raise SystemCallError.new(path, errno) unless errno == Errno::EACCES::Errno
      return unless $VERBOSE

      Primitive.zr_warn_here_m("#{path}: #{SystemCallError.new(nil, errno).message}")
    end

    def emit(path)
      @found << path.force_encoding(@enc)
    end

    # glob_helper: the parts in `parts` at `path`, whose kind is `type`.
    def helper(path, baselen, namelen, dirsep, type, parts, flags)
      plain = magical = recursive = match_all = match_dir = brace = false
      parts.each do |part|
        if part.type == RECURSIVE
          recursive = true
          part = part.next
        end
        case part.type
        when PLAIN then plain = true
        when ALPHA then @real_basename ? plain = true : magical = true
        when BRACE then brace = true if !recursive || part.str.include?("/")
        when MAGICAL then magical = true
        when MATCH_ALL then match_all = true
        when MATCH_DIR then match_dir = true
        end
      end
      if brace
        Glob.expand_braces(joined(parts.first).force_encoding(@enc), @escape).each do |each|
          helper(path, baselen, namelen, dirsep, type, [make_pattern(each.b)], flags)
        end
        return
      end
      unless path.empty?
        type = kind_of(path, false) if match_all && type == UNKNOWN
        type = kind_of(path, true) if match_dir && (type == UNKNOWN || type == SYMLINK)
        skip = baselen + (baselen.positive? && at(path, baselen) == 0x2F ? 1 : 0)
        emit(path.byteslice(skip, path.bytesize - skip)) if match_all && type > NOENT
        emit(path.byteslice(skip, path.bytesize - skip) + (dirsep ? "/".b : "".b)) if match_dir && type == DIRECTORY
      end
      return if type == NOENT

      if magical || recursive
        walk(path, baselen, namelen, dirsep, parts, flags, recursive)
      elsif plain
        plainly(path, baselen, namelen, dirsep, parts, flags)
      end
    end

    # The entries of a directory, each against every part.
    def walk(path, baselen, namelen, dirsep, parts, flags, _recursive)
      where = path.empty? ? ".".b : path
      entries = IO.send(:gc_for_fd) { Primitive.zr_io_dir_kinds(where.dup.force_encoding(@enc)) }
      return opendir_failed(where, -entries) if entries.is_a?(Integer)

      flags |= File::FNM_CASEFOLD if @real_basename && Primitive.zr_io_pathconf(where, 11) == 0
      pairs = Array.new(entries.size / 2) { |i| [entries[2 * i].b, entries[(2 * i) + 1]] }
      pairs.sort! { |a, b| a[0] <=> b[0] } if (flags & NOSORT).zero?
      skipdot = (flags & SKIPDOT) != 0
      flags |= SKIPDOT
      dotmatch = (flags & File::FNM_DOTMATCH) != 0
      pathlen = baselen + namelen
      pairs.each do |name, kind|
        name = name.b
        new_type = UNKNOWN
        dotfile = 0
        if name.getbyte(0) == 0x2E
          dotfile = 1
          if name.bytesize == 1
            next if parts.any? { _1.type == RECURSIVE } && !dotmatch
            next if skipdot

            dotfile = 2
            new_type = DIRECTORY
          elsif name == "..".b
            next
          end
        end
        buf = join(path.byteslice(0, pathlen), dirsep, name)
        new_type = [UNKNOWN, DIRECTORY, SYMLINK, OTHER][kind] if new_type == UNKNOWN && kind.positive?
        if parts.any? { _1.type == RECURSIVE } && dotfile < (dotmatch ? 2 : 1) && new_type == UNKNOWN
          new_type = kind_of(buf, false)
        end
        next_parts = []
        parts.each do |part|
          if part.type == RECURSIVE
            next_parts << part if (new_type == DIRECTORY || new_type == EXIST) && dotfile < (dotmatch ? 2 : 1)
            part = part.next
          end
          case part.type
          when BRACE
            matched = Glob.expand_braces(part.str.dup.force_encoding(@enc), @escape).any? { |each| match?(each.b, name, flags) }
            next_parts << part.next if matched
          when PLAIN, ALPHA, MAGICAL
            next_parts << part.next if match?(part.str, name, flags)
          end
        end
        helper(buf, baselen, buf.bytesize - baselen, true, new_type, next_parts, flags)
      end
    end

    # The plain parts, each looked up by its name, with the parts that
    # match the same name walked together.
    def plainly(path, baselen, namelen, dirsep, parts, flags)
      copies = parts.map { |part| part.type <= ALPHA ? part : nil }
      pathlen = baselen + namelen
      copies.each_index do |i|
        part = copies[i]
        next unless part

        name = @escape ? unescaped(part.str) : part.str
        next_parts = [part.next]
        ((i + 1)...copies.size).each do |j|
          other = copies[j]
          next unless other && match?(other.str, name, flags)

          next_parts << other.next
          copies[j] = nil
        end
        buf = join(path.byteslice(0, pathlen), dirsep, name)
        new_type = UNKNOWN
        buf, new_type = real_basename(buf, pathlen + (dirsep ? 1 : 0)) if part.type == ALPHA && @real_basename
        helper(buf, baselen, buf.bytesize - baselen, true, new_type, next_parts, flags)
      end
    end

    # remove_backslashes: each backslash goes, one at the end too.
    def unescaped(bytes)
      out = +"".b
      i = 0
      while i < bytes.bytesize
        if bytes.getbyte(i) == 0x5C
          i += 1
          break if i == bytes.bytesize
        end
        n = @onig.mbclen(bytes, i)
        out << bytes.byteslice(i, n)
        i += n
      end
      out
    end

    # replace_real_basename: the last name of the path as the directory
    # spells it, where the volume matches names without their case.
    def real_basename(path, base)
      dir = base.positive? ? path.byteslice(0, base - 1) : "".b
      dir = "/".b if dir.empty? && base == 1
      name = path.byteslice(base, path.bytesize - base)
      entries = Primitive.zr_io_dir_kinds((dir.empty? ? ".".b : dir).dup.force_encoding(@enc))
      if entries.is_a?(Integer)
        # getattrlist needs no descriptor. When the directory does not
        # open for another reason (EMFILE), the name stays as written,
        # and the walk reports the error.
        gone = -entries == Errno::ENOENT::Errno || -entries == Errno::ENOTDIR::Errno
        return [path, gone ? NOENT : UNKNOWN]
      end

      # getattrlist gives the name and the kind of the entry together.
      pairs = Array.new(entries.size / 2) { |i| [entries[2 * i].b, [EXIST, DIRECTORY, SYMLINK, OTHER][entries[(2 * i) + 1]]] }
      real, kind = pairs.find { |each, _| each == name } ||
                   pairs.find { |each, _| each.dup.force_encoding(@enc).casecmp?(name.dup.force_encoding(@enc)) }
      return [path, NOENT] unless real

      [path.byteslice(0, base) + real, kind]
    end
  end
  private_constant :Glob
  # With a block, the directory changes back afterwards; without one
  # it stays. No argument means the home directory.
  def self.chdir(path = (home = true; nil))
    if home
      path = ENV["HOME"] || ENV["LOGDIR"]
      raise ArgumentError, +"HOME/LOGDIR not set" if path.nil?
    end
    path = File.send(:path_of, path)
    check_chdir(block_given?)
    return move_to(path) unless block_given?

    before = pwd
    move_to(path, "dir_chdir0")
    chdir_block(caller_locations(1, 1).first) { yield path }
  ensure
    move_to(before) if before
  end

  # dir.c's chdir lock: a chdir inside another thread's chdir block is
  # an error, and one without a block inside a block of this thread
  # warns, with where that block began.
  def self.check_chdir(block)
    Primitive.attr! :hidden
    return if @chdir_depth.nil? || @chdir_depth.zero?
    raise RuntimeError, +"conflicting chdir during another chdir block" unless Thread.current.equal?(@chdir_thread)
    return if block || $VERBOSE.nil?

    # One warning holds both lines, as dir_chdir0 gives them to rb_warn.
    where = @chdir_where.last
    note = where ? "\n#{where.path}:#{where.lineno}: note: previous chdir was here" : ""
    Primitive.zr_warn_here_m("conflicting chdir during another chdir block#{note}")
  end

  def self.chdir_block(where)
    Primitive.attr! :hidden
    @chdir_depth = (@chdir_depth || 0) + 1
    @chdir_thread = Thread.current
    (@chdir_where ||= []) << where
    yield
  ensure
    @chdir_where.pop
    @chdir_depth -= 1
    @chdir_thread = nil if @chdir_depth.zero?
  end
  private_class_method :check_chdir, :chdir_block

  def self.move_to(path, site = +"chdir_path")
    Primitive.attr! :hidden
    path = File.send(:path_of, path)
    result = File.send(:without_gvl) { Primitive.zr_io_chdir(File.send(:os_path, path)) }
    raise SystemCallError.new(path, -result, site) if result < 0

    0
  end
  private_class_method :move_to
  # This process's home from the environment, a named user's from the
  # password file.
  # dir_s_home: a user named by an empty String is no user at all.
  def self.home(user = nil)
    user = Primitive.zr_str_operand(user) unless user.nil?
    user = nil if user&.empty?
    return Primitive.zr_home_dir(nil) if user.nil? && ENV["HOME"].nil?
    return ENV["HOME"].dup if user.nil?

    Primitive.zr_home_dir(user) || raise(ArgumentError, "user #{user} doesn't exist")
  end
end

module Kernel
  # `test(command, file, other = nil)`: one letter that selects the
  # check on a file, as the shell's own test does.
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
