# IO: a file descriptor with a read buffer and a write buffer.
# `Kernel#puts` and friends write to whatever `$stdout` is, as CRuby's
# do.
class IO
  include Enumerable

  # IO_WBUF_CAPA_MIN: what a stream holds before it writes. A write
  # that would fill the buffer writes what waits and the text with it,
  # as CRuby's io_binwrite does.
  WBUF_CAPA = 8192
  private_constant :WBUF_CAPA

  # The streams that hold bytes nothing has written yet. The end of the
  # program writes them; `exit!` never does, because _exit(2) drops
  # whatever stdio holds.
  PENDING = []
  private_constant :PENDING

  # The seek and wait flags stay IO's own.
  SEEK_SET = 0
  SEEK_CUR = 1
  SEEK_END = 2
  SEEK_HOLE = 3
  SEEK_DATA = 4

  READABLE = 1
  PRIORITY = 2
  WRITABLE = 4

  # O_NONBLOCK, which `File::NONBLOCK` also names. IO answers its own
  # descriptors before File exists, so the flag is IO's own here.
  NONBLOCK = 4
  private_constant :NONBLOCK

  POLL_IN = READABLE
  POLL_PRI = PRIORITY
  POLL_OUT = WRITABLE

  # PIPE_BUF: the amount a ready pipe takes without waiting.
  ATOMIC = 512
  private_constant :POLL_IN, :POLL_PRI, :POLL_OUT, :ATOMIC

  # A pipe's read and write ends, closed after the block when one is
  # given.
  def self.pipe
    reader, writer = pipe_ends.map.with_index { |fd, i| IO.new(fd, i.zero? ? "r" : "w") }
    # rb_io_synchronized: the write end of a pipe holds nothing back,
    # so a reader of the other end sees each write as it happens.
    writer.sync = true
    # rb_pipe marks both ends non-blocking, and a program that asks sees
    # the flag ruby set.
    reader.send(:set_nonblock, true)
    writer.send(:set_nonblock, true)
    return [reader, writer] unless block_given?

    begin
      yield reader, writer
    ensure
      reader.close unless reader.closed?
      writer.close unless writer.closed?
    end
  end

  def self.binread(path, length = nil, offset = nil) = File.read(path, length, offset).b

  def self.binwrite(path, content, offset = nil) = File.write(path, content, offset)

  def self.foreach(path, *args, **options, &block) = File.foreach(path, *args, **options, &block)

  def self.readlines(path, *args, **options) = File.readlines(path, *args, **options)

  def self.read(path, length = nil, offset = nil, **options) = File.read(path, length, offset, **options)

  def self.write(path, content, offset = nil, **options) = File.write(path, content, offset, **options)

  def self.for_fd(fd, mode = "r", **options) = new(fd, mode, **options)

  MODES = %w[r r+ w w+ a a+].freeze
  private_constant :MODES

  # The mode and the options an open takes, as rb_io_extract_modeenc
  # reads them: the access mode, whether the stream is binary, and the
  # encodings named. A mode string names the encodings after a colon,
  # and an option that names one as well is an error.
  def self.open_options(mode, options)
    Primitive.attr! :hidden
    mode = options[:mode] if mode.nil?
    external = nil
    internal = nil
    binary = false
    text = "r"
    if mode.is_a?(Integer)
      text = File.send(:open_mode, mode)
    elsif !mode.nil?
      string = String.try_convert(mode)
      raise TypeError, "no implicit conversion of #{conversion_name(mode)} into String" if string.nil?

      head, external, internal = string.split(":", 3)
      binary = head.include?("b")
      text = head.delete("bt")
      raise ArgumentError, "invalid access mode #{string}" unless MODES.include?(text)
    end
    named = !external.nil?
    external = spec(external)
    internal = spec(internal)
    if options.key?(:encoding) || options.key?(:external_encoding) || options.key?(:internal_encoding)
      raise ArgumentError, "encoding specified twice" if named

      if options.key?(:encoding)
        first, second = options[:encoding].to_s.split(":", 2)
        external = spec(first)
        internal = spec(second)
      end
      # A name an argument gives goes through rb_to_encoding, which
      # raises where a spec warns.
      external, internal = encodings(options.fetch(:external_encoding, external), options.fetch(:internal_encoding, internal))
    end
    binary = true if options[:binmode]
    binary = false if options[:textmode]
    internal = nil if !internal.nil? && !external.nil? && internal.name == external.name
    [text, binary, external, internal]
  end

  # A name a spec gives -- a mode string's tail, or an `encoding:`
  # string -- as parse_mode_enc reads it: a name no encoding answers to
  # warns and leaves the slot at its default, a `-` asks for no
  # transcoding, and a `bom|` prefix leaves the mark to the bytes.
  def self.spec(name)
    Primitive.attr! :hidden
    return name if name.nil? || name.is_a?(Encoding)
    return nil if name == "-" || name == ""

    text = name.start_with?("bom|", "BOM|") ? name[4..] : name
    begin
      Encoding.find(text)
    rescue ArgumentError
      Primitive.zr_warn_here_m("Unsupported encoding #{name} ignored")
      nil
    end
  end

  # What a pair of names stands for: a `-` where the internal encoding
  # goes asks for no transcoding and names no encoding to look up, and
  # an internal one that repeats the external leaves none either.
  def self.encodings(external, internal)
    Primitive.attr! :hidden
    external = Encoding.find(external) unless external.nil? || external.is_a?(Encoding)
    internal = nil if internal == "-" || internal == ""
    internal = Encoding.find(internal) unless internal.nil? || internal.is_a?(Encoding)
    internal = nil if !internal.nil? && !external.nil? && internal.name == external.name
    [external, internal]
  end
  private_class_method :open_options, :encodings, :spec

  # `IO.open` is `IO.new` with a block that closes the stream after it.
  def self.open(*args, **options)
    io = new(*args, **options)
    return io unless block_given?

    begin
      yield io
    ensure
      io.close unless io.closed?
    end
  end

  # The raw descriptor for a path, which is what a program that means to
  # wrap it in its own IO asks for. A creation names its permissions
  # exactly rather than leaving them to the umask.
  def self.sysopen(path, mode = "r", perm = nil)
    path = File.send(:path_of, path)
    if mode.is_a?(Integer) && (mode & File::CREAT).zero?
      fd = Primitive.zr_io_open_flags(path, mode)
      raise SystemCallError.new("@ rb_sysopen - #{path}", -fd) if fd < 0

      return fd
    end
    stream = Primitive.zr_io_open(path, File.send(:open_mode, mode))
    raise SystemCallError.new("@ rb_sysopen - #{path}", -stream) if stream < 0

    fd = Primitive.zr_io_fileno(stream)
    Primitive.zr_io_chmod_fd(fd, perm) if perm
    fd
  end

  # A length any allocator serves, below which a read need not ask. The
  # bounds are written out, because Integer#** reaches Rational, which
  # the core does not have yet while this file loads.
  ROOM_FREELY = 2_147_483_648
  ROOM_AT_MOST = 9_223_372_036_854_775_807
  private_constant :ROOM_FREELY, :ROOM_AT_MOST

  # CRuby fills a read's whole buffer before it reads, so a length no
  # allocator can serve raises NoMemoryError and reads nothing. The
  # answer comes from the machine, not from a limit named here.
  def self.room_for!(length)
    Primitive.attr! :hidden
    return if length.nil? || length < ROOM_FREELY
    raise NoMemoryError, "failed to allocate memory" if length > ROOM_AT_MOST || !Primitive.zr_memory_for_p(length)
  end

  # rb_time_interval: a wait is a number of seconds, and anything else
  # refuses under its own name. A nil waits for good.
  def self.time_interval(value)
    Primitive.attr! :hidden
    return nil if value.nil?
    raise TypeError, "can't convert #{conversion_name(value)} into time interval" unless value.is_a?(Numeric)
    raise ArgumentError, "time interval must not be negative" if value.negative?

    value
  end

  # select(2) over three lists of streams: the ones that came ready, or
  # nil when the time ran out. A nil timeout waits for good.
  def self.select(readers, writers = nil, priority = nil, timeout = nil)
    timeout = time_interval(timeout)
    milliseconds = timeout.nil? ? -1 : (timeout * 1000).to_i
    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (timeout * 1e9).to_i
    loop do
      ready = [readers, writers, priority].zip([POLL_IN, POLL_OUT, POLL_PRI]).map do |list, event|
        Array(list).select do |io|
          stream = select_stream(io)
          next true if event == POLL_IN && stream.send(:buffered?)

          Primitive.zr_io_wait(stream.fileno, event, 0) & event != 0
        end
      end
      return ready if ready.any? { |list| !list.empty? }
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline
      return nil if milliseconds.zero?

      sleep 0.001
    end
  end

  # What a `select` list entry stands for: a stream, or whatever its
  # `to_io` answers. Anything that has no `to_io` is no stream at all,
  # and ruby says so of it by name.
  def self.select_stream(entry)
    Primitive.attr! :hidden
    return entry if entry.is_a?(IO)
    raise TypeError, "no implicit conversion of #{conversion_name(entry)} into IO" unless entry.respond_to?(:to_io)

    stream = entry.to_io
    raise TypeError, "can't convert #{conversion_name(entry)} to IO (#{conversion_name(entry)}#to_io gives #{conversion_name(stream)})" unless stream.is_a?(IO)

    stream
  end
  private_class_method :select_stream

  # Runs the command with a pipe on its standard input or output. With
  # a block the stream closes and the child is waited for after it, and
  # the block's value is the answer.
  def self.popen(*args, **options)
    env = args.first.is_a?(Hash) ? args.shift : nil
    command, mode = args
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

    io = popen_stream(command, (mode || "r").to_s, options, env)
    return io unless block_given?

    begin
      yield io
    ensure
      io.close
    end
  end

  # A pipe's two descriptors, or a SystemCallError.
  def self.pipe_ends
    ends = Primitive.zr_io_pipe
    raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

    ends
  end

  # A child with a pipe on its standard output ("r"), one on its
  # standard input ("w"), or one on each ("r+"): the handle of a
  # read-write mode reads the first pipe and writes the second.
  def self.popen_stream(command, mode, options, env = nil)
    duplex = mode.include?("+")
    reading = duplex || mode.start_with?("r")
    raise ArgumentError, "invalid access mode #{mode}" unless reading || mode.start_with?("w", "a")

    read_fd, write_fd = pipe_ends
    ours, theirs = reading ? [read_fd, write_fd] : [write_fd, read_fd]
    plan = { (reading ? 1 : 0) => theirs, ours => :close }
    twin = nil
    child_in = nil
    if duplex
      child_in, twin = pipe_ends
      plan[0] = child_in
      plan[twin] = :close
    end
    words = Array(command)
    pid = Process.send(:spawn_command, env ? [env, *words] : words, plan.merge(options))
    Primitive.zr_io_close(theirs)
    Primitive.zr_io_close(child_in) if child_in
    if pid.nil?
      Primitive.zr_io_close(ours)
      Primitive.zr_io_close(twin) if twin
      raise SystemCallError.new(Process.send(:command_words, words).first, 2)
    end
    stream = new(ours, duplex ? "r+" : (reading ? "r" : "w"), pid: pid, twin: twin)
    # A popen stream is synchronous, as CRuby's pipe_open marks it.
    stream.sync = true
    stream
  end

  private_class_method :pipe_ends, :popen_stream

  def self.try_convert(object) = object.respond_to?(:to_io) ? object.to_io : nil

  # Everything one stream holds, written to the other.
  # A source is anything that answers `read`, or a path; a sink is
  # anything that answers `write`, or a path. That is what lets a
  # StringIO stand on either side.
  def self.copy_stream(from, to, length = nil, offset = nil)
    text = if from.respond_to?(:read)
             offset ? (from.seek(offset); from.read(length)) : from.read(length)
           else
             File.read(from, length, offset)
           end
    text = text.to_s
    to.respond_to?(:write) ? to.write(text) : File.write(to, text)
  end

  def initialize(fd, mode = nil, **options)
    # A descriptor is a C int, as NUM2INT reads it. The bounds are
    # written out: the standard streams open before Integer#** can run.
    fd = Primitive.zr_index_operand_m(fd)
    raise RangeError, "integer #{fd} too big to convert to 'int'" if fd > 2147483647
    raise RangeError, "integer #{fd} too small to convert to 'int'" if fd < -2147483648

    rows = Primitive.zr_fstat_m(fd)
    raise SystemCallError.new("@ rb_io_initialize", -rows) if rows.is_a?(Integer)

    text, binary, external, internal = IO.send(:open_options, mode, options)
    @fd = fd
    @mode = text
    # What the mode allows, decided once: every read and write asks.
    @readable = !text.start_with?("w", "a") || text.include?("+")
    @writable = !text.start_with?("r") || text.include?("+")
    # A duplex popen writes to a second descriptor, the twin of this
    # one: the child's standard input, where this one is its output.
    @twin = options[:twin]
    check_access
    @external = external
    @internal = internal
    @binmode = binary
    @autoclose = options.fetch(:autoclose, true) && fd > 2
    @path = options[:path]
    @name = options[:name]
    @pid = options[:pid]
    @closed = false
    @sync = false
    # O_NONBLOCK as this stream set it. Asking the descriptor here would
    # cost an fcntl for every stream a program opens, including the three
    # the runtime opens before a program starts, and `nonblock?` asks the
    # descriptor itself whenever a program wants the truth.
    @nonblock = false
    # FMODE_TTY: a terminal writes at once, as a synchronous stream does.
    @tty = Primitive.zr_io_tty_p(fd)
    @lineno = 0
    @buffer = fresh_buffer
    @wbuf = +"".b
    @eof = false
  end

  attr_reader :lineno

  def path = @path || @name
  attr_reader :sync

  # A stream that becomes synchronous writes what it holds at once.
  def sync=(flag)
    @sync = flag
    write_pending if flag && !@closed
    flag
  end

  def lineno=(n)
    @lineno = n
  end

  def fileno
    check_open
    @fd
  end

  alias to_i fileno

  def tty?
    check_open
    Primitive.zr_io_tty_p(@fd)
  end

  alias isatty tty?

  def closed? = @closed

  def close
    return nil if @closed

    write_pending
    @closed = true
    if @twin
      Primitive.zr_io_close(@twin)
      @twin = nil
    end
    result = @autoclose ? Primitive.zr_io_close(@fd) : 0
    raise SystemCallError.new(nil, -result) if result < 0

    Process.wait(@pid) if @pid
    nil
  end

  # `dup` and `clone` open a fresh descriptor onto the same file, so a
  # close or a reopen of one leaves the other where it was.
  def initialize_copy(other)
    fd = Primitive.zr_io_dup(other.fileno)
    raise SystemCallError.new("@ rb_io_dup", -fd) if fd < 0

    @fd = fd
    @buffer = fresh_buffer
    @wbuf = +"".b
    @tty = Primitive.zr_io_tty_p(fd)
    @closed = false
    self
  end

  # `reopen`: this stream's descriptor number comes to name the other
  # stream's open file, so every reference already held follows along.
  # That is what saving and restoring $stdout is built on.
  def reopen(other, mode = nil)
    check_open
    write_pending
    other = File.open(other, mode || @mode) unless other.is_a?(IO)
    result = Primitive.zr_io_dup2(other.fileno, @fd)
    raise SystemCallError.new("@ rb_io_reopen - #{label}", -result) if result < 0

    @path = other.path
    @buffer = fresh_buffer
    @eof = false
    @lineno = 0
    self
  end

  def flush
    check_open
    write_pending
    self
  end

  def fsync
    check_open
    write_pending
    Primitive.zr_io_fsync(@fd)
    0
  end

  # Every stream that holds bytes, written out. The end of the program
  # calls this, and a stream that cannot take them any more is not the
  # program's to hear about.
  def self.flush_pending
    Primitive.attr! :hidden
    until PENDING.empty?
      io = PENDING.pop
      begin
        io.send(:write_pending)
      rescue SystemCallError, IOError
        nil
      end
    end
    nil
  end

  # CRuby flushes the two standard streams before it starts a child, so
  # that what the parent holds cannot arrive after what the child writes.
  def self.flush_std
    Primitive.attr! :hidden
    [$stdout, $stderr].each do |io|
      io.flush if io.is_a?(IO) && !io.closed?
    rescue SystemCallError, IOError
      nil
    end
    nil
  end

  # Binary mode: what is read from here on is binary, and so is what the
  # buffer already holds.
  def binmode
    @binmode = true
    # Binary mode answers for the stream's encoding, whatever name it
    # was opened with.
    @external = nil
    @internal = nil
    @buffer.force_encoding(Encoding::BINARY)
    self
  end

  def binmode? = @binmode

  def fdatasync = fsync

  def to_path = path

  # A stream opened from a descriptor has no path behind it, so its
  # rows come from fstat(2).
  def stat
    check_open
    path ? File.stat(path) : File::Stat.for_fd(@fd)
  end

  # fcntl(2) on the stream's own descriptor: F_GETFD reads the
  # close-on-exec flag, F_GETFL the flags it was opened with, and a
  # command that takes a number takes it here too. rb_fcntl reads nil and
  # false as 0 and true as 1; a command whose argument is a struct, as a
  # file lock is, has none that fits in a word.
  def fcntl(command, argument = 0)
    check_open
    command = Numeric.send(:int_operand, command)
    value = case argument
            when nil, false then 0
            when true then 1
            when String then Primitive.zr_unimplemented("IO#fcntl with a struct argument")
            else Numeric.send(:int_operand, argument)
            end

    result = Primitive.zr_io_fcntl(@fd, command, value)
    # rb_sys_fail_path names the stream, and the call that set up the
    # argument, after the message; a stream with no path names neither.
    raise SystemCallError.new(path.nil? ? nil : "@ finish_narg - #{path}", -result) if result < 0

    result
  end

  # posix_fadvise is a hint, and darwin has none: ruby answers nil
  # wherever the call is absent.
  def advise(kind, offset = 0, length = 0)
    check_open
    raise NotImplementedError, "advise" unless %i[normal sequential random willneed dontneed noreuse].include?(kind)

    nil
  end

  # Half-closing an end the stream does not have is an error; on one it
  # does have, and which is not duplex, it closes the whole stream.
  def close_read
    raise IOError, "closing non-duplex IO for reading" if @mode.start_with?("w", "a") && !@mode.include?("+")

    close
  end

  # A duplex handle half-closes for real: the twin goes and the child
  # reads its end of input, while what it answers stays readable here.
  def close_write
    raise IOError, "closing non-duplex IO for writing" if @mode.start_with?("r") && !@mode.include?("+")
    return close unless @twin

    write_pending
    fd = @twin
    @twin = nil
    @writable = false
    result = Primitive.zr_io_close(fd)
    raise SystemCallError.new(nil, -result) if result < 0

    nil
  end

  # The child a popen started, waited for when this stream closes.
  attr_reader :pid

  def autoclose? = @autoclose

  def autoclose=(flag)
    @autoclose = flag ? true : false
    flag
  end

  # A descriptor ruby opens closes itself across an exec.
  def close_on_exec? = true

  def close_on_exec=(flag)
    flag
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) unless block

    read.each_codepoint(&block)
    self
  end

  alias codepoints each_codepoint

  # `pread` and `pwrite` leave the descriptor's own offset alone.
  # pread(2) and pwrite(2) name a file position and leave the stream's
  # own where it was, buffer included.
  def pread(length, offset, buffer = nil)
    check_readable
    IO.send(:room_for!, length)
    text = Primitive.zr_io_pread(@fd, length, offset)
    raise SystemCallError.new("@ rb_io_pread - #{label}", -text) if text.is_a?(Integer)
    raise EOFError, "end of file reached" if text.nil?

    buffer ? buffer.replace(text) : text
  end

  def pwrite(text, offset)
    check_writable
    result = Primitive.zr_io_pwrite(@fd, Primitive.zr_obj_as_string(text), offset)
    raise SystemCallError.new("@ rb_io_pwrite - #{label}", -result) if result < 0

    result
  end

  def sysseek(offset, whence = SEEK_SET) = seek(offset, whence)

  # The encoding named for this stream, else what the stream stands
  # for: binary where it is binary, the default where it can be read,
  # and none at all for a handle that only writes.
  def external_encoding
    return @external unless @external.nil?
    return Encoding::BINARY if @binmode
    # A stream that writes as well as reads answers for nothing until
    # something names its encoding, as rb_io_external_encoding asks
    # whether the stream is writable rather than write-only.
    return nil unless @readable && !@writable

    Encoding.default_external
  end

  def internal_encoding = @internal

  def set_encoding(external = nil, internal = nil, **)
    if internal.nil? && external.is_a?(String) && external.include?(":")
      external, internal = external.split(":", 2)
    end
    @external, @internal = IO.send(:encodings, external, internal)
    # What is already buffered reads as the new encoding too.
    @buffer.force_encoding(@external) unless @external.nil? || @binmode
    self
  end

  def inspect
    text = "#<#{self.class}:#{label}"
    text = "#{text} (closed)" if @closed
    "#{text}>"
  end

  # The arguments are walked without Array's own methods: a program
  # that redefines one of those must not break the stream it writes
  # the redefinition's report to.
  def write(*objects)
    check_writable
    total = 0
    i = 0
    while i < Primitive.zr_ary_len_m(objects)
      total += write_bytes(Primitive.zr_obj_as_string(Primitive.zr_ary_at_m(objects, i)))
      i += 1
    end
    total
  end

  def syswrite(text) = write(text)

  def <<(object)
    write(object)
    self
  end

  # `$,` goes between the objects and `$\` after the last one, which is
  # what makes `print` and `puts` differ.
  def print(*objects) = IO.print_to(self, objects)

  # One String, the usual call, is its own line: CRuby takes a String
  # as it is and never asks it for `to_s`.
  def puts(*objects)
    if Primitive.zr_ary_len_m(objects) == 1 && (text = Primitive.zr_ary_at_m(objects, 0)).is_a?(String)
      write(text.end_with?("\n") ? text : text + "\n")
      return nil
    end

    IO.lines_of(objects).each { |line| write(line) }
    nil
  end

  # What `puts` writes for `objects`: each one's to_s with a newline
  # unless it ends in one; nil is an empty line; an Array is its
  # items, an empty one nothing; no objects is one empty line.
  def self.lines_of(objects)
    return ["\n"] if objects.empty?

    objects.flat_map do |object|
      if object.is_a?(Array)
        # An array that holds itself shows the marker in its own place
        # rather than walking for ever.
        next ["[...]\n"] if Primitive.zr_recursive_enter(object, :puts)

        begin
          object.empty? ? [] : lines_of(object)
        ensure
          Primitive.zr_recursive_leave(object, :puts)
        end
      else
        text = Primitive.zr_obj_as_string(object)
        text.end_with?("\n") ? [text] : [text + "\n"]
      end
    end
  end

  # What `print` writes `objects` as: their `to_s` joined by `$,`, then
  # `$\`, and `$_` where there are no objects.
  def self.print_to(out, objects)
    objects = [$_] if objects.empty?
    out.write(objects.map(&:to_s).join($, || ""))
    out.write($\) if $\
    nil
  end

  def printf(format, *args)
    write(Kernel.format(format, *args))
    nil
  end

  def p(*objects)
    i = 0
    while i < Primitive.zr_ary_len_m(objects)
      write(Primitive.zr_ary_at_m(objects, i).inspect, "\n")
      i += 1
    end
    Primitive.zr_ary_len_m(objects) <= 1 ? Primitive.zr_ary_at_m(objects, 0) : objects
  end

  # `read(length)`: that many bytes, fewer at the end, nil past it, and
  # always binary; without a length, everything that is left.
  def read(length = nil, buffer = nil)
    check_readable
    raise ArgumentError, "negative length #{length} given" if length && length < 0

    IO.send(:room_for!, length)
    if length.nil?
      fill until @eof
      out = transcoded(@buffer)
      @buffer = fresh_buffer
    else
      fill while !@eof && @buffer.bytesize < length
      return nil if @buffer.empty? && length > 0

      out = take(length).force_encoding(Encoding::BINARY)
    end
    buffer ? buffer.replace(out) : out
  end

  # These three all read what is there and fill a buffer when one is
  # given; the end of the stream is an error, not a nil.
  def sysread(length, buffer = nil) = filled(read_some(length), buffer)

  def readpartial(length, buffer = nil) = filled(read_some(length), buffer)

  # CRuby writes these three in Ruby (its io.rb), so they answer their
  # own parameters, under CRuby's names.
  def read_nonblock(len, buf = nil, exception: true)
    Primitive.attr! :ruby
    check_readable
    raise ArgumentError, "negative length #{len} given" if len < 0
    if !buffered? && !len.zero? && would_block?(READABLE)
      return :wait_readable unless exception

      raise EAGAINWaitReadable, "Resource temporarily unavailable - read would block"
    end
    text = read_some(len)
    return nil if text.nil? && !exception

    filled(text, buf)
  end

  def write_nonblock(buf, exception: true)
    Primitive.attr! :ruby
    check_writable
    text = buf.is_a?(String) ? buf : buf.to_s
    if would_block?(WRITABLE)
      return :wait_writable unless exception

      raise EAGAINWaitWritable, "Resource temporarily unavailable - write would block"
    end
    # What waits in the buffer goes first, so the bytes keep their order.
    write_pending
    wrote = Primitive.zr_io_write_some(@twin || @fd, text, 0, text.bytesize)
    if wrote < 0 && -wrote == Errno::EAGAIN::Errno
      return :wait_writable unless exception

      raise EAGAINWaitWritable, "Resource temporarily unavailable - write would block"
    end
    checked_write(wrote)
  end

  def putc(c)
    write(c.is_a?(Integer) ? (c & 0xff).chr : c.to_s[0, 1])
    c
  end

  # The byte setup_narg writes after a buffer, which the answer must
  # leave alone, and the mask that reads a command's own length.
  IOCTL_SENTINEL = 17
  IOCPARM_MASK = 0x1fff
  private_constant :IOCTL_SENTINEL, :IOCPARM_MASK

  # ioctl(2). rb_io_ctl reads the argument as setup_narg does: nil and
  # false are 0, true is 1, an Integer stands for itself, and a String is
  # the buffer the command fills -- grown to the length the command names,
  # with one byte after it that the answer must not reach.
  def ioctl(command, argument = 0)
    Primitive.attr! :ruby
    check_open
    command = Numeric.send(:int_operand, command)
    buffer = ioctl_buffer(command, argument)
    result = if buffer.nil?
               Primitive.zr_io_ioctl(@fd, command, ioctl_narg(argument))
             else
               Primitive.zr_io_ioctl_buf(@fd, command, buffer)
             end
    raise SystemCallError.new(path.nil? ? nil : "@ finish_narg - #{path}", -result) if result < 0
    return result if buffer.nil?

    # finish_narg: the sentinel says the command wrote no further than
    # the room the buffer gave it.
    raise ArgumentError, "return value overflowed string" unless buffer.getbyte(buffer.bytesize - 1) == IOCTL_SENTINEL

    buffer.setbyte(buffer.bytesize - 1, 0)
    result
  end

  # The number a command reads when it fills no buffer.
  def ioctl_narg(argument)
    Primitive.attr! :hidden
    return 0 if argument.nil? || argument.equal?(false)
    return 1 if argument.equal?(true)

    Numeric.send(:int_operand, argument)
  end

  # The String a command fills, as long as the command names plus the
  # sentinel. Anything that is not a String fills no buffer.
  def ioctl_buffer(command, argument)
    Primitive.attr! :hidden
    return nil if argument.nil? || argument.equal?(true) || argument.equal?(false) || argument.is_a?(Integer)

    text = String.try_convert(argument)
    return nil if text.nil?

    room = ((command >> 16) & IOCPARM_MASK) + 1
    text.replace(text + ("\0" * (room - text.bytesize))) if text.bytesize < room
    text.setbyte(text.bytesize - 1, IOCTL_SENTINEL)
    text
  end

  def timeout = @timeout

  def timeout=(seconds)
    @timeout = seconds
  end

  # A byte order mark at the head of the stream names the encoding.
  def set_encoding_by_bom
    return nil unless pos.zero?

    lead = read(3)
    return nil if lead.nil?

    if lead.start_with?("\xEF\xBB\xBF".b)
      ungetc(lead[3..].to_s)
      return set_encoding(Encoding::UTF_8)
    end
    ungetc(lead)
    nil
  end

  # One character: a UTF-8 lead byte brings its continuation bytes.
  def getc
    first = read(1)
    return nil if first.nil?

    lead = first.getbyte(0)
    more = if lead >= 0xF0 then 3
           elsif lead >= 0xE0 then 2
           elsif lead >= 0xC2 then 1
           else 0
           end
    more > 0 ? first + (read(more) || "") : first
  end

  def readchar = getc || raise(EOFError, "end of file reached")

  def getbyte = read(1)&.getbyte(0)

  def readbyte = getbyte || raise(EOFError, "end of file reached")

  # An Integer here is a codepoint, not the text of a number.
  def ungetc(text)
    @buffer = (text.is_a?(Integer) ? text.chr(@buffer.encoding) : text.to_s) + @buffer
    nil
  end

  # An Integer here is one byte, not the text of a number.
  def ungetbyte(byte)
    @buffer = (byte.is_a?(Integer) ? (byte & 0xff).chr : byte.to_s) + @buffer
    nil
  end

  # A line up to and with `separator`; "" separates paragraphs; nil
  # reads to the end. `limit` caps the bytes.
  def gets(*args, chomp: false)
    check_readable
    separator, limit = getline_args(args)
    line = transcoded(read_line(separator, limit))
    $_ = nil
    return nil if line.nil?

    @lineno += 1
    $. = @lineno
    $_ = chomp ? chomp_line(line, separator) : line
  end

  def readline(sep = (nosep = true), limit = (nolimit = true), chomp: false)
    Primitive.attr! :ruby
    args = nosep ? [] : (nolimit ? [sep] : [sep, limit])
    gets(*args, chomp: chomp) || raise(EOFError, "end of file reached")
  end

  def each_line(*args, chomp: false)
    return to_enum(:each_line, *args, chomp: chomp) unless block_given?

    separator, limit = getline_args(args)
    while (line = gets(separator, limit, chomp: chomp))
      yield line
    end
    self
  end

  alias each each_line

  def readlines(*args, chomp: false)
    each_line(*args, chomp: chomp).to_a
  end

  def each_char
    return to_enum(:each_char) unless block_given?

    while (c = getc)
      yield c
    end
    self
  end

  def each_byte
    return to_enum(:each_byte) unless block_given?

    while (b = getbyte)
      yield b
    end
    self
  end

  def eof?
    check_readable
    fill if @buffer.empty? && !@eof
    @buffer.empty? && @eof
  end

  alias eof eof?

  def pos
    check_open
    write_pending
    result = Primitive.zr_io_seek(@fd, 0, SEEK_CUR)
    raise SystemCallError.new("@ rb_io_tell - #{label}", -result) if result < 0

    result - @buffer.bytesize
  end

  alias tell pos

  def seek(offset, whence = SEEK_SET)
    check_open
    write_pending
    whence = { set: SEEK_SET, cur: SEEK_CUR, end: SEEK_END }.fetch(whence) if whence.is_a?(Symbol)
    offset -= @buffer.bytesize if whence == SEEK_CUR
    @buffer = fresh_buffer
    @eof = false
    result = Primitive.zr_io_seek(@fd, offset, whence)
    raise SystemCallError.new("@ rb_io_seek - #{label}", -result) if result < 0

    0
  end

  def pos=(offset)
    seek(offset)
    offset
  end

  def rewind
    seek(0)
    @lineno = 0
    0
  end

  def to_io = self

  private

  def label
    Primitive.attr! :hidden
    @name || @path || "fd #{@fd}"
  end

  def mark_closed
    Primitive.attr! :hidden
    @closed = true
  end

  def check_open
    Primitive.attr! :hidden
    raise IOError, "closed stream" if @closed
  end

  # A system call on a descriptor that is not ready would stop every
  # green thread, so a task that shares the process with others hands
  # the turn on until the descriptor answers. A lone task waits in the
  # system call itself, or in poll(2) when the descriptor cannot wait.
  def park_until(event, fd = @fd)
    Primitive.attr! :hidden
    until !Primitive.zr_threaded || Thread.send(:alone?)
      return if Primitive.zr_io_wait(fd, event, 0) != 0

      sleep 0.001
    end
    Primitive.zr_io_wait(fd, event, -1) if @nonblock
  end

  # Whether a call on this descriptor would wait. A non-blocking call
  # asks this first and then makes the ordinary call, which a descriptor
  # that is ready answers at once.
  def would_block?(event)
    Primitive.attr! :hidden
    ready = Primitive.zr_io_wait(@fd, event, 0)
    ready <= 0 || (ready & event).zero?
  end

  # O_NONBLOCK on the descriptor itself. Every call on it then waits in
  # select(2) before the call rather than inside it, which is what lets a
  # green sibling run while this task waits.
  def set_nonblock(on)
    Primitive.attr! :hidden
    answer = Primitive.zr_io_set_nonblock(@fd, on ? 1 : 0)
    raise SystemCallError.new("@ set_nonblock - #{label}", -answer) unless answer.zero?

    @nonblock = on
  end

  # The flag as the descriptor itself holds it, which another process or
  # an accepted socket can have set.
  def nonblock_flag?
    Primitive.attr! :hidden
    flags = Primitive.zr_io_flags(@fd)
    flags >= 0 && (flags & NONBLOCK) != 0
  end

  # The bytes out, in pieces a ready descriptor takes without waiting:
  # one write(2) of a whole 200KB string blocks until the reader drains
  # the pipe, and a green sibling is the only one who can drain it.
  # CRuby's io_binwrite: a synchronous stream and a terminal write at
  # once. Anything else fills the buffer, and a write that would fill it
  # writes what waits and the text together.
  def write_bytes(text)
    Primitive.attr! :hidden
    return write_now(text) if @sync || @tty

    if @wbuf.bytesize + text.bytesize < WBUF_CAPA
      PENDING << self if @wbuf.empty?
      @wbuf << text.b
      return text.bytesize
    end
    waiting = @wbuf
    @wbuf = +"".b
    PENDING.delete(self)
    write_now(waiting + text) - waiting.bytesize
  end

  # What the buffer holds, written out.
  def write_pending
    Primitive.attr! :hidden
    return nil if @wbuf.empty?

    waiting = @wbuf
    @wbuf = +"".b
    PENDING.delete(self)
    write_now(waiting)
    nil
  end

  def write_now(text)
    Primitive.attr! :hidden
    fd = @twin || @fd
    return checked_write(Primitive.zr_io_write(fd, text)) if !@nonblock && (!Primitive.zr_threaded || Thread.send(:alone?))

    from = 0
    size = text.bytesize
    # A descriptor that cannot wait takes what it has room for and says
    # how much; a blocking one is fed in pieces it always has room for.
    piece = @nonblock ? size : ATOMIC
    while from < size
      park_until(WRITABLE, fd)
      wrote = Primitive.zr_io_write_some(fd, text, from, piece)
      # A descriptor can still say "not yet" after select(2) said it was
      # ready, so the write comes round again.
      if wrote < 0 && -wrote == Errno::EAGAIN::Errno
        Thread.pass
        next
      end
      from += checked_write(wrote)
    end
    size
  end

  def checked_write(result)
    Primitive.attr! :hidden
    raise SystemCallError.new("@ io_write - #{label}", -result) if result < 0

    result
  end

  # What a read answered, into `buffer` when one was given. The end of
  # the stream is an error here, not a nil.
  # What one read(2) gives: what waits in the buffer already, else one
  # fill of it. A partial read never waits for the whole length, so a
  # reader of a pipe answers as soon as anything arrives.
  def read_some(length)
    Primitive.attr! :hidden
    check_readable
    raise ArgumentError, "negative length #{length} given" if length < 0
    return "".b if length.zero?

    IO.send(:room_for!, length)

    fill if @buffer.empty? && !@eof
    return nil if @buffer.empty?

    take([length, @buffer.bytesize].min).force_encoding(Encoding::BINARY)
  end

  def filled(text, buffer)
    Primitive.attr! :hidden
    raise EOFError, "end of file reached" if text.nil?

    buffer ? buffer.replace(text) : text
  end

  def check_readable
    Primitive.attr! :hidden
    check_open
    raise IOError, "not opened for reading" unless @readable
  end

  def check_writable
    Primitive.attr! :hidden
    check_open
    raise IOError, "not opened for writing" unless @writable
  end

  # More bytes into the buffer; none marks the end.
  def fill
    Primitive.attr! :hidden
    park_until(READABLE)
    chunk = Primitive.zr_io_read(@fd, 8192)
    if chunk.nil?
      @eof = true
    elsif chunk.is_a?(Integer)
      # A descriptor that cannot wait says "nothing yet" rather than
      # waiting, so the read comes round again.
      # A directory answers EISDIR only on the read, which ruby reports
      # from the outer call rather than the buffer filler.
      site = -chunk == Errno::EISDIR::Errno ? "io_fread" : "io_fillbuf"
      raise SystemCallError.new("@ #{site} - #{label}", -chunk) unless -chunk == Errno::EAGAIN::Errno

      Thread.pass
    else
      # The bytes join the buffer as they stand: the buffer's own
      # encoding decides what was read, not the chunk's.
      chunk.force_encoding(@buffer.encoding)
      @buffer << chunk
    end
  end

  # An empty read buffer in the stream's encoding: binary in binary mode.
  # The access a mode asks for must be one the descriptor carries, as
  # rb_io_initialize checks it with fcntl.
  # Bytes a read already took from the descriptor and did not hand out.
  # A stream that holds them is ready to read whatever the descriptor
  # itself would say.
  def buffered?
    Primitive.attr! :hidden
    !@buffer.empty?
  end

  def check_access
    Primitive.attr! :hidden
    # A duplex handle writes to its twin, so this descriptor only has
    # to allow what a read asks for.
    return if @twin

    flags = Primitive.zr_io_flags(@fd)
    raise SystemCallError.new(nil, -flags) if flags < 0
    return if (flags & 3) == 2

    raise Errno::EINVAL unless (@readable && @writable ? 2 : (@writable ? 1 : 0)) == (flags & 3)
  end

  # An internal encoding converts what was read on the way in, which is
  # what naming both ends of a stream asks for.
  def transcoded(text)
    Primitive.attr! :hidden
    return text if text.nil? || @internal.nil?

    text.encode(@internal, @external || Encoding.default_external)
  end

  # What is read arrives in the stream's own encoding: binary where the
  # stream is binary, else the external encoding it was opened with.
  def fresh_buffer
    Primitive.attr! :hidden
    return "".b if @binmode

    text = +""
    text.force_encoding(@external) unless @external.nil?
    text
  end

  # gets' arguments as ruby reads them: one argument is the separator
  # when it is nil or converts to a String, else the limit; of two, the
  # first must convert to a String.
  def getline_args(args)
    Primitive.attr! :hidden
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

    separator = $/
    limit = nil
    if args.size == 1
      text = args[0].nil? ? nil : String.try_convert(args[0])
      if args[0].nil? || text
        separator = text
      else
        limit = args[0]
      end
    elsif args.size == 2
      separator, limit = args
      separator = Primitive.zr_str_operand(separator) unless separator.nil?
    end
    [separator, limit.nil? ? nil : implicit_integer(limit)]
  end

  def read_line(separator, limit)
    Primitive.attr! :hidden
    if separator.nil?
      fill until @eof
      return nil if @buffer.empty?

      return take(limit ? whole_char(limit) : @buffer.bytesize)
    end
    paragraph = separator.empty?
    separator = "\n\n" if paragraph
    if paragraph
      fill while !@eof && @buffer.start_with?("\n")
      @buffer = @buffer.byteslice(1, @buffer.bytesize - 1) || +"" while @buffer.start_with?("\n")
    end
    while true
      # A byte offset: `take` counts bytes, and a character index would
      # also walk the whole buffer for every line.
      at = Primitive.zr_str_find_from(@buffer, separator, 0)
      if at
        stop = at + separator.bytesize
        stop = whole_char([stop, limit].min) if limit
        line = take(stop)
        if paragraph
          fill while !@eof && @buffer.start_with?("\n")
          @buffer = @buffer.byteslice(1, @buffer.bytesize - 1) || +"" while @buffer.start_with?("\n")
        end
        return line
      end
      return take(whole_char(limit)) if limit && @buffer.bytesize >= limit
      break if @eof

      fill
    end
    return nil if @buffer.empty?

    take(@buffer.bytesize)
  end

  # A limit that falls inside a character grows to that character's
  # end, as ruby's does, never past what the buffer holds. A binary
  # stream counts bytes.
  def whole_char(n)
    Primitive.attr! :hidden
    fill while !@eof && @buffer.bytesize <= n
    return [n, @buffer.bytesize].min if @binmode

    n += 1 while n < @buffer.bytesize && (@buffer.getbyte(n) & 0xC0) == 0x80
    [n, @buffer.bytesize].min
  end

  # The first `n` bytes out of the buffer, which keeps the rest.
  def take(n)
    Primitive.attr! :hidden
    Primitive.zr_str_shift_front(@buffer, n)
  end

  def chomp_line(line, separator)
    Primitive.attr! :hidden
    return line.chomp if separator == "\n" || separator == ""

    line.end_with?(separator) ? line[0, line.bytesize - separator.bytesize] : line
  end
end

STDIN = IO.new(0, "r", name: "<STDIN>")
STDOUT = IO.new(1, "w", name: "<STDOUT>")
STDERR = IO.new(2, "w", name: "<STDERR>")
STDERR.sync = true
$stdin = STDIN
$stdout = STDOUT
$stderr = STDERR
alias $> $stdout
alias $PROGRAM_NAME $0

# Kernel's output goes to `$stdout`: through its own methods when it
# is an IO, else through its `write`, as CRuby does with any object
# put there.
module Kernel
  def puts(*objects)
    out = $stdout
    return out.puts(*objects) if out.is_a?(IO)

    IO.send(:lines_of, objects).each { |line| out.write(line) }
    nil
  end

  # `$,` goes between the objects and `$\` after the last one, which is
  # what makes `print` and `puts` differ. `$stdout` is asked for `write`
  # and nothing else, so an object that stands in for it needs only that
  # one method, which is all CRuby needs of it.
  def print(*objects) = IO.print_to($stdout, objects)

  # Alone among the writers, `p` flushes: CRuby's rb_f_p ends with
  # `rb_io_flush` when `$stdout` is an IO, so what `p` wrote survives
  # an `exit!` while what `puts` or `print` wrote does not.
  def p(*objects)
    out = $stdout
    i = 0
    while i < Primitive.zr_ary_len_m(objects)
      out.write(Primitive.zr_ary_at_m(objects, i).inspect, "\n")
      i += 1
    end
    out.flush if out.is_a?(IO)
    Primitive.zr_ary_len_m(objects) <= 1 ? Primitive.zr_ary_at_m(objects, 0) : objects
  end

  def printf(format = nil, *args)
    return nil if format.nil?

    if format.is_a?(IO)
      format.printf(*args)
    else
      $stdout.write(Kernel.format(format, *args))
    end
    nil
  end

  # A bare read reads ARGF: the files ARGV names, and standard input
  # where it names none.
  def gets(*args, **options) = ARGF.gets(*args, **options)

  def readline(*args, **options) = ARGF.readline(*args, **options)

  def readlines(*args, **options) = ARGF.readlines(*args, **options)

  def open(path, *rest, **options, &block)
    Primitive.zr_unimplemented("Kernel#open of a pipe") if path.is_a?(String) && path.start_with?("|")

    File.open(path, *rest, **options, &block)
  end

  private :puts, :print, :p, :printf, :gets, :readline, :readlines, :open
  module_function :puts, :print, :p, :printf, :gets, :readline, :readlines, :open
end

# The errors libSystem answers, each a class under Errno with the
# errno it stands for.
class SystemCallError
  # The errno hides from reflection, as ruby's does.
  def errno = Primitive.zr_hidden_get(self, :__errno__)

  # `SystemCallError.new(message, errno)` answers the Errno class for
  # the errno when one exists.
  def self.new(message = nil, errno = nil)
    if message.is_a?(Integer) && errno.nil?
      errno = message
      message = nil
    end
    klass = errno && self == SystemCallError ? Errno.for(errno) || self : self
    error = klass.allocate
    error.send(:initialize, message, errno)
    error
  end

  def initialize(message = nil, errno = nil)
    errno = self.class::Errno if errno.nil? && self.class.const_defined?(:Errno)
    Primitive.zr_hidden_set(self, :__errno__, errno)
    text = errno ? Errno.text(errno) : "unknown error"
    text = message.start_with?("@") ? "#{text} #{message}" : "#{text} - #{message}" unless message.nil?
    super(text)
  end

  # A rescue of an Errno class catches the errors with its errno, as
  # CRuby's syserr_eqq decides; SystemCallError itself catches them all.
  def self.===(other)
    if other.is_a?(SystemCallError)
      return true if equal?(SystemCallError)
    elsif !other.respond_to?(:errno)
      return false
    end
    # `rb_const_get`, which reaches Object too: on SystemCallError
    # itself the name finds the top-level Errno module, and a module
    # equals no errno, so a duck never matches the bare class.
    const_defined?(:Errno) && other.errno == const_get(:Errno)
  end
end

# One class for each row of rt/core/errno.rb, and its other names.
module Errno
  CODES.each do |name, code|
    klass = Class.new(SystemCallError)
    klass.const_set(:Errno, code)
    const_set(name, klass)
  end
  ALIASES.each { |name, to| const_set(name, const_get(to)) }

  def self.for(code) = CODES.key(code)&.then { |name| const_get(name) }

  def self.text(code)
    message = Primitive.zr_io_strerror(code)
    message.start_with?("Unknown error") ? "Unknown error: #{code}" : message
  end
end

# How a non-blocking call reports "would block": the error class the
# caller rescues carries the direction as a module.
class IO
  module WaitReadable; end
  module WaitWritable; end

  class TimeoutError < IOError; end

  class EAGAINWaitReadable < Errno::EAGAIN
    include WaitReadable
  end

  class EAGAINWaitWritable < Errno::EAGAIN
    include WaitWritable
  end

  class EINPROGRESSWaitReadable < Errno::EINPROGRESS
    include WaitReadable
  end

  class EINPROGRESSWaitWritable < Errno::EINPROGRESS
    include WaitWritable
  end

  # EWOULDBLOCK is EAGAIN on this platform, so the names are one class.
  EWOULDBLOCKWaitReadable = EAGAINWaitReadable
  EWOULDBLOCKWaitWritable = EAGAINWaitWritable
end

# Waiting on one descriptor, over poll(2). Named events answer the
# stream itself; a plain events mask answers the events that came ready.
class IO
  EVENT_NAMES = { read: POLL_IN, readable: POLL_IN, r: POLL_IN,
                  write: POLL_OUT, writable: POLL_OUT, w: POLL_OUT,
                  priority: POLL_PRI, rw: POLL_IN | POLL_OUT }.freeze
  private_constant :EVENT_NAMES

  def wait(*args)
    if args.size == 2 && args.all? { |arg| arg.is_a?(Numeric) }
      ready = poll_once(args[0].to_int, args[1])
      return ready.zero? ? nil : ready
    end
    events = 0
    timeout = nil
    args.each do |arg|
      case arg
      when Symbol then events |= EVENT_NAMES.fetch(arg) { raise ArgumentError, "unsupported mode: #{arg}" }
      when Numeric, nil then timeout = arg
      else raise TypeError, "can't convert #{conversion_name(arg)} into time interval"
      end
    end
    poll_once(events.zero? ? POLL_IN : events, timeout).zero? ? nil : self
  end

  def wait_readable(timeout = nil) = poll_once(POLL_IN, timeout).zero? ? nil : self

  def wait_writable(timeout = nil) = poll_once(POLL_OUT, timeout).zero? ? nil : self

  def wait_priority(timeout = nil) = poll_once(POLL_PRI, timeout).zero? ? nil : self

  private

  # The events that came ready, or zero when the time ran out.
  def poll_once(events, timeout)
    timeout = IO.send(:time_interval, timeout)
    ready = Primitive.zr_io_wait(fileno, events, timeout.nil? ? -1 : (timeout * 1000).round)
    raise SystemCallError.new("@ io_wait - #{label}", -ready) if ready.negative?

    ready & events
  end
end
