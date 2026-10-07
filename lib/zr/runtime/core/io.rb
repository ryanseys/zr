# frozen_string_literal: true

# IO: a file descriptor with a read buffer and a write buffer.
# `Kernel#puts` and friends write to whatever `$stdout` is, as CRuby's
# do.
class IO
  include Enumerable

  # IO_WBUF_CAPA_MIN: how many bytes a stream buffers before it writes.
  # A write that would fill the buffer writes the waiting bytes and the
  # new text together, as CRuby's io_binwrite does.
  WBUF_CAPA = 8192
  NEWLINE = "\n".freeze
  # The encodings whose characters take more than one byte each: the
  # size of their code unit and where a newline's byte is in it.
  WIDE_UNITS = { "UTF-16BE" => [2, 1], "UTF-16LE" => [2, 0], "UTF-32BE" => [4, 3], "UTF-32LE" => [4, 0],
                 "UTF-16" => [2, 1], "UTF-32" => [4, 3] }.freeze
  private_constant :WBUF_CAPA, :NEWLINE, :WIDE_UNITS

  # The streams that contain bytes not yet written. The end of the
  # program writes them. `exit!` never does, because _exit(2) discards
  # all that stdio buffers.
  PENDING = []
  private_constant :PENDING

  # The descriptor of a stream that owns it and has it open. The stream's
  # finalizer closes it when the collector frees the stream, as CRuby's
  # fptr_finalize does. A stream with buffered bytes is in PENDING, so the
  # collector never frees one that still has bytes to write. At the end
  # of the program the descriptors stay open: the program's own
  # finalizers run then, and they may still write.
  class Closer
    attr_writer :fd

    def initialize(fd)
      @fd = fd
    end

    def call(_id)
      Primitive.attr! :hidden
      fd = @fd
      @fd = nil
      Primitive.zr_io_close(fd) if fd && !Primitive.zr_finalizing_at_exit
    end
  end
  private_constant :Closer

  # The wait flags stay IO's own; the seek flags are the OS's.
  READABLE = 1
  PRIORITY = 2
  WRITABLE = 4

  POLL_IN = READABLE
  POLL_PRI = PRIORITY
  POLL_OUT = WRITABLE

  # PIPE_BUF: the amount a ready pipe takes without waiting.
  ATOMIC = 512
  private_constant :POLL_IN, :POLL_PRI, :POLL_OUT, :ATOMIC

  # A pipe's read and write ends, closed after the block when one is
  # given. The encodings are the read end's, and `binmode:` is both ends'.
  # Both ends are instances of the class it is called on, as rb_io_s_pipe
  # makes them.
  def self.pipe(external = nil, internal = nil, **options)
    # rb_class_new_instance: the class allocates and its initialize runs; a
    # `new` that the program wrote is not called.
    reader, writer = pipe_ends.map.with_index { |fd, i| allocate.tap { |io| io.send(:initialize, fd, i.zero? ? +"r" : +"w") } }
    binmode = options.delete(:binmode)
    reader.set_encoding(external, internal, **options) if external
    # rb_io_s_pipe: `binmode:` with an encoding sets binary mode only, and
    # the encoding stays; with none, both ends read and write binary.
    if binmode
      [reader, writer].each { |io| external ? io.send(:binary_mode_flag) : io.binmode }
    end
    # rb_io_synchronized: the write end of a pipe buffers nothing, so a
    # reader of the other end sees each write immediately.
    writer.sync = true
    # rb_pipe marks both ends non-blocking, and a program that checks sees
    # the flag that ruby set.
    reader.send(:set_nonblock, true)
    writer.send(:set_nonblock, true)
    return [reader, writer] unless block_given?

    begin
      yield reader, writer
    ensure
      closing(reader)
      closing(writer)
    end
  end

  # rb_io_s_binread opens the file binary, so no default encoding
  # converts what it reads.
  def self.binread(path, length = nil, offset = nil)
    File.open(File.send(:path_of, path), "rb") do |file|
      file.seek(offset) if offset
      length ? file.read(length) : file.read
    end
  end

  def self.binwrite(path, content, offset = nil, **options) = written(path, content, offset, true, options)

  # CRuby's rb_io_s_read takes a fourth argument, which the read it
  # passes on then refuses.
  def self.read(path, length = nil, offset = nil, extra = (none = true; nil), **options)
    raise ArgumentError, +"wrong number of arguments (given 3, expected 0..2)" unless none
    raise ArgumentError, "negative offset #{offset} given" if offset && (offset = IO.send(:offset_of, offset)).negative?

    opened(File.send(:path_of, path), options[:mode].nil? ? "r" : nil, options) do |file|
      file.seek(offset) if offset
      length ? file.read(length) : file.read
    end
  end

  def self.write(path, content, offset = nil, **options) = written(path, content, offset, false, options)

  # io_s_write: with no mode given, the file is made where it is missing
  # and cut short only where no offset says where the write goes.
  def self.written(path, content, offset, binary, options)
    Primitive.attr! :hidden
    options = options.merge(mode: File::WRONLY | File::CREAT | (offset ? 0 : File::TRUNC)) if options[:mode].nil?
    opened(File.send(:path_of, path), nil, options) do |file|
      file.binmode if binary
      file.seek(offset) if offset
      file.write(content)
    end
  end
  private_class_method :written

  # The options of an open belong to the open, as rb_io_extract_modeenc
  # takes them; only `chomp:` belongs to the lines.
  # The separator and the limit convert before the file opens.
  def self.readlines(path, *args, **options)
    line = options.key?(:chomp) ? { chomp: options.delete(:chomp) } : {}
    path = File.send(:path_of, path)
    args = line_args(args)
    opened(path, options[:mode].nil? ? "r" : nil, options) { |file| file.readlines(*args, **line) }
  end

  # Each line is also `$_`, which is nil at the end.
  def self.foreach(path, *args, **options, &block)
    return to_enum(:foreach, path, *args, **options) unless block

    line = options.key?(:chomp) ? { chomp: options.delete(:chomp) } : {}
    path = File.send(:path_of, path)
    args = line_args(args)
    opened(path, options[:mode].nil? ? "r" : nil, options) do |file|
      file.send(:each_line_for, :foreach, args, line.fetch(:chomp, false)) do |text|
        $_ = text
        yield text
      end
    end
    $_ = nil
  end

  # gets' arguments, converted, in a form that converts again to the same.
  def self.line_args(args)
    Primitive.attr! :hidden
    return args if args.empty?

    separator, limit = allocate.send(:getline_args, args)
    [separator, limit || -1]
  end

  # open_key_args: an :open_args Array is the whole of the open, and the
  # other options do not count.
  def self.opened(path, mode, options, &block)
    Primitive.attr! :hidden
    given = options[:open_args]
    return File.open(path, mode, **options, &block) if given.nil?

    given = Array.try_convert(given) or raise TypeError, "no implicit conversion of #{given.class} into Array"
    keywords = given.last.is_a?(Hash) ? given.last : {}
    positional = keywords.empty? && !given.last.is_a?(Hash) ? given : given[0...-1]
    raise ArgumentError, "wrong number of arguments (given #{positional.size + 1}, expected 1..3)" if positional.size > 2

    File.open(path, *positional, **keywords, &block)
  end
  private_class_method :opened, :line_args

  # rb_io_s_new: a block here is a mistake, which ruby names.
  def self.new(*args, **options, &block)
    Primitive.zr_warn_here_m("#{self}::new() does not take block; use #{self}::open() instead") if block
    built(args, options)
  end

  # rb_class_new_instance: an instance and its initialize, with no frame
  # of `new` between, as rb_io_s_open makes one.
  def self.built(args, options)
    Primitive.attr! :hidden
    io = allocate
    io.__send__(:initialize, *args, **options)
    io
  end
  private_class_method :built

  # rb_io_s_for_fd: IO's own initialize, whatever the receiver, so a File
  # takes a descriptor here where its initialize takes a path.
  def self.for_fd(fd, mode = nil, **options)
    io = allocate
    IO.instance_method(:initialize).bind_call(io, fd, mode, **options)
    io
  end

  # io_strip_bom's marks, longest first where two share a head.
  BOMS = [["\xEF\xBB\xBF".b, "UTF-8"], ["\xFE\xFF".b, "UTF-16BE"], ["\xFF\xFE\x00\x00".b, "UTF-32LE"],
          ["\xFF\xFE".b, "UTF-16LE"], ["\x00\x00\xFE\xFF".b, "UTF-32BE"]].freeze
  private_constant :BOMS

  MODES = %w[r r+ w w+ a a+].freeze
  private_constant :MODES

  # The mode and the options an open takes, as rb_io_extract_modeenc
  # reads them: the access mode, whether the stream is binary, the given
  # encodings, and how the stream converts what it reads and writes. A
  # mode string gives the encodings after a colon, and an option that
  # also gives one is an error.
  def self.open_options(mode, options)
    Primitive.attr! :hidden
    unless options[:mode].nil?
      raise ArgumentError, +"mode specified twice" unless mode.nil?

      mode = options[:mode]
    end
    mode = Integer.try_convert(mode) || mode unless mode.nil? || mode.is_a?(String)
    external = internal = nil
    binary = textual = named = bom = false
    text = +"r"
    if mode.is_a?(Integer)
      text = File.send(:open_mode, mode)
    elsif !mode.nil?
      string = String.try_convert(mode)
      raise TypeError, "no implicit conversion of #{conversion_name(mode)} into String" if string.nil?

      head, tail = string.split(":", 2)
      text = access_mode(string)
      binary = head.include?("b")
      textual = head.include?("t")
      external, internal, bom = mode_encodings(tail) if (named = !tail.nil?)
    end
    unless options[:flags].nil?
      flags = (mode.is_a?(Integer) ? mode : File.send(:open_flags, text)) | implicit_integer(options[:flags])
      text = File.send(:open_mode, flags)
    end
    binary, textual = binmode_options(options, binary, textual)
    if options.key?(:encoding) || options.key?(:external_encoding) || options.key?(:internal_encoding)
      raise ArgumentError, +"encoding specified twice" if named

      # rb_io_extract_encoding_option: :encoding goes through to_str, and
      # :external_encoding or :internal_encoding wins over it, with a warning.
      if options.key?(:encoding) && !options[:encoding].nil?
        given = options[:encoding]
        given = String.try_convert(given) || given unless given.is_a?(Encoding)
        if options.key?(:external_encoding) || options.key?(:internal_encoding)
          used = options.key?(:external_encoding) ? "external_encoding" : "internal_encoding"
          warn("Ignoring encoding parameter '#{given}': #{used} is used", uplevel: 0) unless $VERBOSE.nil?
        elsif given.is_a?(Encoding)
          external = given
        else
          # parse_mode_enc, as for a mode string: `bom|` and the warnings.
          external, internal, bom = mode_encodings(given.to_s)
        end
      end
      # A name an argument gives goes through rb_to_encoding, which
      # raises where a spec warns.
      if options.key?(:external_encoding) || options.key?(:internal_encoding)
        external, internal = encodings(options.fetch(:external_encoding, external), options.fetch(:internal_encoding, internal))
      end
    end
    # With a byte order mark, the mark may change the external encoding,
    # so an internal one that repeats it stays.
    internal = nil if !bom && !internal.nil? && !external.nil? && internal.name == external.name
    internal = nil if Encoding::BINARY.equal?(external)
    readable = !text.start_with?("w", "a") || text.include?("+")
    conversion = conversion_options(options, readable && textual && !binary)
    check_binmode(readable, binary, external, internal, conversion)
    [text, binary, external, internal, conversion.merge(bom: bom)]
  end

  # parse_mode_enc: "ext", "ext:int" or "ext:-", split at the last colon.
  # A name that matches no encoding warns and leaves its slot at the
  # default, and `bom|` before a UTF encoding lets the bytes give it.
  def self.mode_encodings(spec)
    Primitive.attr! :hidden
    at = spec.rindex(":")
    name = at ? spec[0, at] : spec
    bom = false
    if name.bytesize > 4 && name[0, 4].casecmp?("bom|")
      name = name[4..]
      spec = spec[4..]
      at -= 4 if at
      if name[0, 3].casecmp?("utf")
        bom = true
      else
        Primitive.zr_warn_here_m("BOM with non-UTF encoding #{spec} is nonsense")
      end
    end
    external = name.empty? ? nil : (Encoding.find(name) rescue nil)
    Primitive.zr_warn_here_m("Unsupported encoding #{name.empty? ? spec : name} ignored") if external.nil?
    return [external, nil, bom] if at.nil?

    tail = spec[(at + 1)..]
    return [external, nil, bom] if tail == +"-"

    internal = tail.empty? ? nil : (Encoding.find(tail) rescue nil)
    Primitive.zr_warn_here_m("Unsupported encoding #{tail} ignored") if internal.nil?
    # rb_io_ext_int_to_encs: an internal encoding with no external one
    # names the default external, the same one twice converts nothing,
    # and nothing converts from binary.
    external ||= Encoding.default_external unless internal.nil?
    internal = nil if (!bom && internal.equal?(external)) || Encoding::BINARY.equal?(external)
    [external, internal, bom]
  end

  # NUM2INT: a Float truncates, and the value must fit a C int.
  def self.c_int(value)
    Primitive.attr! :hidden
    value = Float === value ? value.to_i : implicit_integer(value)
    raise RangeError, +"bignum too big to convert into 'long'" unless value.bit_length < 64
    raise RangeError, "integer #{value} too big to convert to 'int'" if value > 2_147_483_647
    raise RangeError, "integer #{value} too small to convert to 'int'" if value < -2_147_483_648

    value
  end

  # rb_io_ext_int_to_encs with no internal encoding given: the default
  # internal encoding converts from the external one, which the stream
  # then keeps, also when the two are the same. With no conversion, an
  # external encoding that was not given stays unset and follows the
  # default. A binary stream converts nothing.
  def self.default_encodings(external)
    Primitive.attr! :hidden
    given = external || Encoding.default_external
    internal = Encoding.default_internal
    return [external, nil] if internal.nil? || Encoding::BINARY.equal?(given)
    return [given, nil] if internal.equal?(given)

    [given, internal]
  end

  # io.c's find_encoding: an Encoding, or the one a String names; a name
  # that matches nothing warns and gives none.
  def self.found_encoding(value)
    Primitive.attr! :hidden
    return value if value.is_a?(Encoding)

    name = Primitive.zr_str_operand(value)
    # A name that is not ASCII is an error, not a name to ignore.
    raise ArgumentError, +"invalid encoding name (non ASCII)" unless name.encoding.ascii_compatible?

    begin
      Encoding.find(name)
    rescue ArgumentError
      Primitive.zr_warn_here_m("Unsupported encoding #{name} ignored")
      nil
    end
  end

  # extract_binmode: `textmode:` and `binmode:` each once, and never both.
  def self.binmode_options(options, binary, textual)
    Primitive.attr! :hidden
    unless options[:textmode].nil?
      raise ArgumentError, +"textmode specified twice" if textual
      raise ArgumentError, +"both textmode and binmode specified" if binary

      textual = true if options[:textmode]
    end
    unless options[:binmode].nil?
      raise ArgumentError, +"binmode specified twice" if binary
      raise ArgumentError, +"both textmode and binmode specified" if textual

      binary = true if options[:binmode]
    end
    raise ArgumentError, +"both textmode and binmode specified" if binary && textual

    [binary, textual]
  end

  # rb_econv_prepare_options for a stream: what a read turns line ends
  # into (only universal applies there), what a write turns them into,
  # and the options each write's conversion takes. A text mode that
  # reads is universal until an option names another line end.
  def self.conversion_options(options, universal)
    Primitive.attr! :hidden
    Encoding.send(:check_options, options)
    given = options.key?(:newline) || %i[universal_newline crlf_newline cr_newline lf_newline].any? { |name| !options[name].nil? }
    lines = given ? Encoding.send(:newline_decorators, options) : (universal ? [:universal_newline] : [])
    encode = options.slice(:invalid, :undef, :replace, :xml).compact
    { lines: lines, encode: encode }
  end

  # validate_enc_binmode.
  def self.check_binmode(readable, binary, external, internal, conversion)
    Primitive.attr! :hidden
    if readable && internal.nil? && !binary && !(external || Encoding.default_external).ascii_compatible?
      raise ArgumentError, +"ASCII incompatible encoding needs binmode"
    end
    raise ArgumentError, +"newline decorator with binary mode" if binary && !conversion[:lines].empty?
  end

  # What a pair of names means. A `-` in the internal position means no
  # transcoding and no encoding to look up. An internal encoding that
  # repeats the external one also gives no internal encoding.
  def self.encodings(external, internal)
    Primitive.attr! :hidden
    external = Encoding.find(external) unless external.nil? || external.is_a?(Encoding)
    internal = nil if internal == +"-" || internal == +""
    internal = Encoding.find(internal) unless internal.nil? || internal.is_a?(Encoding)
    internal = nil if !internal.nil? && !external.nil? && internal.name == external.name
    [external, internal]
  end
  # rb_io_modestr_fmode: `r`, `w` or `a`, then any of `b`, `t` and `+`,
  # and `x` after a `w`, up to the encodings after a colon. It returns
  # the mode without its letters for binary, text and exclusive.
  def self.access_mode(string)
    Primitive.attr! :hidden
    head = string.split(":", 2).first || ""
    first = head[0]
    rest = head[1..] || ""
    valid = %w[r w a].include?(first) && !(rest.include?("b") && rest.include?("t")) &&
            rest.each_char.all? { |c| "bt+".include?(c) || (c == +"x" && first == +"w") }
    raise ArgumentError, "invalid access mode #{string}" unless valid

    rest.include?("+") ? "#{first}+" : first
  end
  private_class_method :open_options, :encodings, :access_mode, :mode_encodings, :binmode_options,
                       :conversion_options, :check_binmode, :found_encoding, :c_int

  # `IO.open` is `new` with a block that closes the stream after it; the
  # receiver's initialize decides what the arguments mean.
  def self.open(*args, **options)
    io = built(args, options)
    return io unless block_given?

    begin
      yield io
    ensure
      closing(io)
    end
  end

  # io_close, after a block: the program's own closed? and close, as
  # rb_check_funcall sends them, and an IOError that says the stream is
  # already closed is no error.
  def self.closing(io)
    Primitive.attr! :hidden
    return if io.__send__(:closed?)

    io.__send__(:close)
  rescue IOError => e
    raise unless e.message == "closed stream"
  end
  private_class_method :closing

  # The raw descriptor for a path, which a program that wants to wrap it
  # in its own IO requests: rb_sysopen, with the permissions that a
  # creation takes, minus the umask.
  # rb_gc_for_fd: a call that finds no free descriptor collects, which
  # closes the descriptors of the streams that the program dropped
  # (Closer), and tries once more. The block returns its result, or a
  # negated errno.
  def self.gc_for_fd
    Primitive.attr! :hidden
    result = yield
    return result unless result.is_a?(Integer) && (-result == Errno::EMFILE::Errno || -result == Errno::ENFILE::Errno)

    Primitive.zr_gc_start
    yield
  end
  private_class_method :gc_for_fd

  def self.sysopen(path, mode = +"r", perm = nil)
    path = File.send(:path_of, path)
    mode = +"r" if mode.nil?
    flags = mode.is_a?(Integer) ? mode : File.send(:open_flags, File.send(:open_mode, mode))
    perm = perm.nil? ? 0o666 : Integer(perm)
    fd = IO.send(:gc_for_fd) { Fiber.send(:offloaded) { Primitive.zr_io_open_flags(File.send(:os_path, path), flags, perm) } }
    raise SystemCallError.new(path, -fd, +"rb_sysopen") if fd < 0

    fd
  end

  # A length that any allocator can supply, below which a read need not
  # check. The bounds are written out, because Integer#** reaches
  # Rational, which the core does not have yet while this file loads.
  ROOM_FREELY = 2_147_483_648
  ROOM_AT_MOST = 9_223_372_036_854_775_807
  private_constant :ROOM_FREELY, :ROOM_AT_MOST

  # CRuby fills a read's whole buffer before it reads, so a length that
  # no allocator can supply raises NoMemoryError and reads nothing. The
  # machine sets the limit, not a constant in this file.
  def self.room_for!(length)
    Primitive.attr! :hidden
    return if length.nil? || length < ROOM_FREELY
    raise NoMemoryError, +"failed to allocate memory" if length > ROOM_AT_MOST || !Primitive.zr_memory_for_p(length)
  end

  # rb_time_interval: a wait is a number of seconds, and anything else
  # refuses under its own name. A nil waits for good.
  def self.time_interval(value)
    Primitive.attr! :hidden
    return nil if value.nil?
    raise TypeError, "can't convert #{conversion_name(value)} into time interval" unless value.is_a?(Numeric)
    raise ArgumentError, +"time interval must not be negative" if value.negative?
    raise RangeError, +"NaN out of Time range" if value.is_a?(Float) && value.nan?

    value
  end

  # select(2) over three lists of streams: the ones that came ready, or
  # nil when the time ran out. A nil timeout waits for good.
  def self.select(readers, writers = nil, priority = nil, timeout = nil)
    scheduler = Fiber.current_scheduler
    return scheduler.io_select(readers, writers, priority, timeout) if scheduler.respond_to?(:io_select)

    timeout = time_interval(timeout)
    # An infinite timeout waits as none does.
    timeout = nil if timeout == Float::INFINITY
    rows = [readers, writers, priority].zip([POLL_IN, POLL_OUT, POLL_PRI]).flat_map do |list, event|
      select_list(list).map { |io| [io, select_stream(io), event] }
    end
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    # A reader whose buffer contains bytes is ready without a wait.
    deadline = if rows.any? { |_, stream, event| event == POLL_IN && stream.send(:buffered?) } then now
               elsif timeout then now + (timeout * 1e9).to_i
               end
    ready = Thread.current.send(:wait_fds, rows.map { |_, stream, _| stream.fileno }, rows.map { |_, _, event| event }, deadline, gives_way: true)
    raise SystemCallError.new(nil, -ready, +"select") if ready.is_a?(Integer)

    chosen = rows.zip(ready).select { |(_, stream, event), got| got.positive? || (event == POLL_IN && stream.send(:buffered?)) }
    return nil if chosen.empty?

    [POLL_IN, POLL_OUT, POLL_PRI].map { |event| chosen.filter_map { |(io, _, wanted), _| io if wanted == event } }
  end

  # What a `select` list entry represents: a stream, or the value that
  # its `to_io` returns. An object with no `to_io` is not a stream, and
  # ruby gives its name in the error.
  # Each list is an Array or nil, as rb_f_select's Check_Type wants: a
  # bare IO is an error, not a list of its own lines.
  def self.select_list(list)
    Primitive.attr! :hidden
    return [] if list.nil?
    raise TypeError, "wrong argument type #{conversion_name(list)} (expected Array)" unless list.is_a?(Array)

    list
  end

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
  # a block, the stream closes and the child is waited for after the
  # block, and the block's value is the return value.
  def self.popen(*args, **options, &block)
    # rb_io_s_popen: a Hash after the command is the options, also when
    # it comes as a positional argument (`popen(cmd, *[{err: ...}])`).
    if options.empty? && args.size > 1 && (last = Hash.try_convert(args.last))
      args.pop
      options = last
    end
    env = Hash.try_convert(args.first) if args.size > 1
    args.shift if env
    command, mode = args
    mode = Primitive.zr_str_operand(mode) unless mode.nil? || mode.is_a?(Integer)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if args.empty?
    return popen_fork((mode || "r").to_s, &block) if command == +"-"

    mode ||= options[:mode]
    io = popen_stream(command, (mode || "r").to_s, options, env)
    return io unless block_given?

    begin
      yield io
    ensure
      io.close
    end
  end

  # `popen("-")`: a fork whose standard output ("r"), input ("w") or both
  # ("r+") are pipes to the parent, which gets the stream; the child gets
  # nil. With a block both run it, and the child ends after it, as
  # popen_finish ends it.
  def self.popen_fork(mode)
    Primitive.attr! :hidden
    duplex = mode.include?("+")
    reading = duplex || mode.start_with?("r")
    raise ArgumentError, "invalid access mode #{mode}" unless reading || mode.start_with?("w", "a")

    output = pipe_ends if reading
    input = pipe_ends if duplex || !reading
    pid = Process.send(:call_fork)
    if pid.zero?
      Primitive.zr_io_dup2(output[1], 1) if output
      Primitive.zr_io_dup2(input[0], 0) if input
      [*output, *input].each { |fd| Primitive.zr_io_close(fd) }
      # The child's standard streams write at once, as pipe_open makes
      # them synchronous.
      STDOUT.sync = true
      STDERR.sync = true
      return nil unless block_given?

      begin
        yield nil
      ensure
        $stdout.flush
        $stderr.flush
        Primitive.zr_exit_now(0)
      end
    end
    Primitive.zr_io_close(output[1]) if output
    Primitive.zr_io_close(input[0]) if input
    ours = output ? output[0] : input[1]
    stream = new(ours, duplex ? +"r+" : (reading ? +"r" : +"w"), pid: pid, twin: duplex ? input[1] : nil)
    stream.sync = true
    return stream unless block_given?

    begin
      yield stream
    ensure
      stream.close
    end
  end

  # A pipe's two descriptors, or a SystemCallError.
  def self.pipe_ends
    Primitive.attr! :hidden
    ends = Primitive.zr_io_pipe
    raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

    ends
  end

  # A child with a pipe on its standard output ("r"), one on its
  # standard input ("w"), or one on each ("r+"): the handle of a
  # read-write mode reads the first pipe and writes the second.
  # The options that a popen stream opens with; the rest go to spawn,
  # as rb_execarg_extract_options leaves them.
  STREAM_OPTIONS = %i[mode flags external_encoding internal_encoding encoding textmode binmode autoclose invalid undef
                      replace xml newline universal_newline crlf_newline cr_newline lf_newline].freeze
  private_constant :STREAM_OPTIONS

  def self.popen_stream(command, mode, options, env = nil)
    Primitive.attr! :hidden
    stream_options = options.slice(*STREAM_OPTIONS)
    options = options.except(*STREAM_OPTIONS)
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
    # A Hash at the start of the command Array is the child's environment,
    # under the one given before the command (rb_exec_getargs).
    if command.is_a?(Array) && (first = Hash.try_convert(words.first))
      words = words.drop(1)
      raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if words.empty?

      env = env ? first.merge(env) : first
    end
    # A Hash at the end of the command Array is more exec options; its
    # words are read as a spawn reads them (check_hash).
    if words.size > 1 && (extra = Process.send(:hash_argument, words.last))
      words = words[0...-1]
      options = extra.merge(options)
    end
    # An Array command runs with no shell, also one of a single word.
    words = [[words.first, words.first]] if command.is_a?(Array) && words.size == 1 && words.first.is_a?(String)
    pid = Process.send(:spawn_command, env ? [env, *words] : words, plan.merge(options))
    Primitive.zr_io_close(theirs)
    Primitive.zr_io_close(child_in) if child_in
    if pid.negative?
      Primitive.zr_io_close(ours)
      Primitive.zr_io_close(twin) if twin
      raise SystemCallError.new(Process.send(:command_words, words).first, -pid)
    end
    mode = "w#{mode[1..]}" if mode.start_with?("a")
    stream = new(ours, mode, pid: pid, twin: twin, **stream_options.except(:mode))
    # A popen stream is synchronous, as CRuby's pipe_open marks it.
    stream.sync = true
    stream
  end

  private_class_method :pipe_ends, :popen_stream, :popen_fork

  # rb_io_check_io: #to_io must give an IO.
  def self.try_convert(object)
    return object if IO === object

    io = Primitive.zr_check_call(object, :to_io)
    raise TypeError, "can't convert #{conversion_name(object)} to IO (#{conversion_name(object)}#to_io gives #{conversion_name(io)})" unless io.nil? || IO === io

    io
  end

  COPY_CHUNK = 16 * 1024
  private_constant :COPY_CHUNK

  # rb_io_s_copy_stream: bytes from `src` to `dst`, and how many. Each
  # end is an IO, a path opened for the copy and closed after it, or any
  # object that reads with `readpartial` or `read`, or writes with
  # `write`. A length copies at most that many bytes and an offset reads
  # from there without moving the source; a negative one is none given.
  def self.copy_stream(src, dst, copy_length = nil, src_offset = nil)
    length = copy_length.nil? ? -1 : offset_of(copy_length)
    offset = src_offset.nil? ? -1 : offset_of(src_offset)
    opened = []
    total = 0
    begin
      from = copy_end(src, File::RDONLY, opened)
      from&.send(:check_readable)
      from&.send(:check_byte_readable)
      to = copy_end(dst, File::WRONLY | File::CREAT | File::TRUNC, opened)
      to&.send(:check_writable)
      dst = to if to
      to&.binmode

      if offset.negative? && from&.send(:buffered?)
        held = from.send(:buffered_bytes, length)
        to ? to.send(:write_bytes, held) : dst.write(held)
        total += held.bytesize
        length -= held.bytesize unless length.negative?
      end
      to&.flush
      return total if length.zero?

      if from.nil? || to.nil?
        raise ArgumentError, +"cannot specify src_offset for non-IO" if from.nil? && !offset.negative?

        total += copy_fallback(from || src, dst, from.nil?, length, offset)
      else
        total += copy_descriptors(from, to, length, offset, opened.include?(from))
      end
      total
    ensure
      opened.each(&:close)
    end
  end

  # NUM2OFFT.
  def self.offset_of(value)
    Primitive.attr! :hidden
    case value
    when Integer then value
    when Float then value.to_i
    when String then raise TypeError, +"no implicit conversion from string"
    when true, false then raise TypeError, +"no implicit conversion from boolean"
    else Primitive.zr_index_operand_m(value)
    end.tap { |offset| raise RangeError, +"bignum too big to convert into 'long long'" unless offset.bit_length < 64 }
  end

  # interpret_seek_whence: :SET, :CUR and :END, and the two that find
  # data and holes, else a C int.
  WHENCE = { SET: 0, CUR: 1, END: 2, DATA: 3, HOLE: 4 }.freeze
  private_constant :WHENCE

  def self.whence_of(whence)
    Primitive.attr! :hidden
    WHENCE.fetch(whence) { c_int(whence) }
  end

  # An end of a copy as the IO it reads or writes, opening a path with
  # `flags`; nil for an object that is not a stream and not a file name.
  def self.copy_end(target, flags, opened)
    Primitive.attr! :hidden
    return nil if target.equal?(ARGF) || !(target.is_a?(IO) || target.is_a?(String) || target.respond_to?(:to_path))

    io = try_convert(target)
    return io if io
    return target if target.is_a?(IO)

    file = File.new(File.send(:path_of, target), flags, 0o666)
    opened << file
    file
  end

  # copy_stream_fallback_body: a chunk at a time through the objects'
  # own methods, until the length or the end of the source.
  def self.copy_fallback(src, dst, foreign, length, offset)
    Primitive.attr! :hidden
    total = 0
    rest = length
    reader = foreign && !src.respond_to?(:readpartial) ? :read : :readpartial
    buf = Primitive.zr_str_set_binary(+"")
    while true
      if length.negative?
        size = COPY_CHUNK
      else
        break buf.clear if rest.zero?

        size = [COPY_CHUNK, rest].min
      end
      if foreign
        break if src.__send__(reader, size, buf).nil? && reader == :read
      else
        chunk = src.send(:copy_read, size, offset)
        raise EOFError, +"end of file reached" if chunk.nil?

        buf.replace(chunk)
        offset += chunk.bytesize unless offset.negative?
      end
      wrote = offset_of(dst.write(buf))
      total += wrote
      rest -= wrote
      break if reader == :read && buf.empty?
    end
    total
  rescue EOFError
    total
  end

  # nogvl_copy_stream_read_write: read(2) or pread(2) of the source into
  # write(2) of the destination.
  def self.copy_descriptors(from, to, length, offset, opened)
    Primitive.attr! :hidden
    if !offset.negative? && opened
      from.seek(offset)
      offset = -1
    end
    total = 0
    while length.negative? || length.positive?
      chunk = from.send(:copy_read, length.negative? ? COPY_CHUNK : [length, COPY_CHUNK].min, offset)
      break if chunk.nil?

      offset += chunk.bytesize unless offset.negative?
      total += to.send(:write_now, chunk)
      length -= chunk.bytesize unless length.negative?
    end
    total
  end

  private_class_method :offset_of, :copy_end, :copy_fallback, :copy_descriptors

  def initialize(fd, mode = nil, **options)
    # A descriptor is a C int, as NUM2INT reads it. The bounds are
    # written out: the standard streams open before Integer#** can run.
    fd = Primitive.zr_index_operand_m(fd)
    raise RangeError, "integer #{fd} too big to convert to 'int'" if fd > 2147483647
    raise RangeError, "integer #{fd} too small to convert to 'int'" if fd < -2147483648

    rows = Primitive.zr_fstat_m(fd)
    raise SystemCallError.new(nil, -rows) if rows.is_a?(Integer)

    # A stream that gives no mode takes the one that the descriptor was
    # opened with, as rb_io_initialize gets it from fcntl(2).
    if mode.nil? && options[:mode].nil? && !options[:twin]
      flags = Primitive.zr_io_flags(fd)
      unless flags.negative?
        access = flags & ACCESS.fetch(:mask)
        mode = flags.anybits?(File::APPEND) ? +"a" : (access == ACCESS.fetch(:read) ? +"r" : +"w")
        mode += "+" if access == ACCESS.fetch(:both)
      end
    end
    text, binary, external, internal, conversion = IO.send(:open_options, mode, options)
    external, internal = IO.send(:default_encodings, external) if internal.nil? && !binary
    @fd = fd
    @mode = text
    # What the mode allows, decided once: every read and write checks it.
    @readable = !text.start_with?("w", "a") || text.include?("+")
    @writable = !text.start_with?("r") || text.include?("+")
    # A duplex popen writes to a second descriptor, the twin of this
    # one: the child's standard input, where this one is its output.
    @twin = options[:twin]
    check_access
    @external = external
    @internal = internal
    @binmode = binary
    converting(conversion)
    @autoclose = options.fetch(:autoclose, true) && fd > 2
    @path = options[:path]
    @name = options[:name]
    @pid = options[:pid]
    @closed = false
    own_descriptor
    @sync = false
    # O_NONBLOCK as this stream set it. A query to the descriptor here
    # would cost an fcntl for every stream that a program opens, including
    # the three that the runtime opens before a program starts.
    # `nonblock?` queries the descriptor itself when a program needs the true value.
    @nonblock = false
    # FMODE_TTY: a terminal writes at once, as a synchronous stream does.
    @tty = Primitive.zr_io_tty_p(fd)
    @lineno = 0
    clear_buffer
    @wbuf = +"".b
    @eof = false
    strip_bom if conversion[:bom] && @readable
  end

  # rb_io_check_byte_readable: a stream that converts what it reads keeps
  # characters, not bytes, while an ungetc has put some back at the head
  # of the buffer (CRuby's cbuf). A character read takes all it cooks, as
  # CRuby's converter stops after its first output.
  def check_byte_readable
    Primitive.attr! :hidden
    raise IOError, +"byte oriented read for character buffered IO" if (@universal || @internal) && @char_front.positive?
  end

  # The newline decorators and the options that a stream's conversions
  # take. A read turns line ends into "\n" only with the universal
  # decorator; a write takes crlf, cr or lf, never universal.
  def converting(conversion)
    Primitive.attr! :hidden
    lines = conversion[:lines]
    @universal = lines.include?(:universal_newline)
    # Bytes at the head of the buffer that the universal decorator has
    # already read, so each byte is cooked once; the first `@char_front`
    # of them are characters that ungetc put back.
    @cooked = 0
    @char_front = 0
    written = (lines - [:universal_newline]).first
    @read_options = conversion[:encode].except(:xml)
    @write_options = conversion[:encode].dup
    @write_options[:newline] = written.to_s.delete_suffix("_newline").to_sym if written
    # A UTF-16 or UTF-32 stream writes its byte order mark once, before
    # its first character.
    @bom_written = false
    # A stateful encoding's converter, which lives from the first write
    # to the close.
    @write_converter = nil
    @read_converter = nil
    @read_error = nil
    @read_rest = nil
  end

  def lineno
    check_readable
    @lineno
  end

  # rb_io_path: a new String each time.
  def path = (@path || @name)&.dup

  def sync
    check_open
    @sync
  end

  # A stream that becomes synchronous writes its buffered bytes immediately.
  def sync=(flag)
    check_open
    @sync = flag ? true : false
    write_pending if flag
    flag
  end

  def lineno=(n)
    check_readable
    @lineno = IO.send(:c_int, n)
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

  def closed?
    raise IOError, +"uninitialized stream" if @fd.nil?

    @closed
  end

  def close
    raise IOError, +"uninitialized stream" if @fd.nil?
    return nil if @closed

    # rb_io_close_m checks no freeze: a frozen stream closes too. A core
    # ivar has no `@` in its name.
    finish_writing
    write_pending
    Primitive.zr_state_set(self, :closed, true)
    own_descriptor
    Thread.send(:fd_closed, @fd) if Primitive.zr_threaded
    if @twin
      twin = @twin
      Fiber.send(:offloaded) { Primitive.zr_io_close(twin) }
      Primitive.zr_state_set(self, :twin, nil)
    end
    if @autoclose
      # A non-blocking fiber's scheduler may close the descriptor itself;
      # otherwise close(2) of a stream that writes may block, and its
      # scheduler may run it elsewhere (maygvl_close).
      scheduler = Fiber.current_scheduler
      unless scheduler.respond_to?(:io_close) && scheduler.io_close(@fd)
        fd = @fd
        result = @writable ? Fiber.send(:offloaded) { Primitive.zr_io_close(fd) } : Primitive.zr_io_close(fd)
        raise SystemCallError.new(nil, -result) if result < 0
      end
    end

    reap_child if @pid
    nil
  end

  # rb_syswait: the child that a popen started is waited for, and `$?`
  # takes its status. A child that the program already waited for leaves
  # `$?` cleared, with no error.
  private def reap_child
    Primitive.attr! :hidden
    pid = @pid
    Primitive.zr_state_set(self, :pid, nil)
    Process.send(:status!, nil)
    Process.wait(pid)
  rescue Errno::ECHILD
    nil
  end

  # `dup` and `clone` open a fresh descriptor onto the same file, so a
  # close or a reopen of one leaves the other where it was.
  def initialize_copy(other)
    @fd = fd = cloexec_dup(other.fileno)
    # rb_io_init_copy: a duplex handle's write end is copied too.
    @twin = cloexec_dup(@twin) if @twin
    @autoclose = true
    clear_buffer
    @wbuf = +"".b
    @tty = Primitive.zr_io_tty_p(fd)
    @closed = false
    @closer = nil
    own_descriptor
    self
  end

  # rb_cloexec_dup: a copy of `fd` that closes on exec.
  def cloexec_dup(fd)
    Primitive.attr! :hidden
    copy = Primitive.zr_io_dup(fd)
    raise SystemCallError.new(nil, -copy) if copy < 0

    flags = Primitive.zr_io_fcntl(copy, F_GETFD, 0)
    Primitive.zr_io_fcntl(copy, F_SETFD, flags | FD_CLOEXEC) unless flags.negative?
    copy
  end

  # `reopen`: this stream's descriptor number comes to refer to the other
  # stream's open file, so every existing reference follows along.
  # Saving and restoring $stdout uses this.
  # rb_io_reopen: one argument that converts with #to_io is a stream;
  # anything else is a path, opened in the given mode or in this stream's.
  def reopen(other, mode = nil, **options)
    if mode.nil? && options.empty? && (io = IO.try_convert(other))
      return reopen_stream(io)
    end

    other = File.send(:path_of, other)
    opened = File.open(other, mode || @mode, **options)
    if @closed
      # A closed stream takes the new descriptor itself, as rb_sysopen
      # gives one to a stream that has none.
      @fd = opened.fileno
      opened.autoclose = false
      @closed = false
      @autoclose = @fd > 2
      own_descriptor
    else
      write_pending
      dup_from(opened.fileno, other)
    end
    adopt_mode(opened.send(:mode_state)) if mode || !options.empty?
    opened.close unless opened.closed?
    @path = other
    clear_buffer
    @eof = false
    self
  end

  # io_reopen: this descriptor number comes to refer to the other
  # stream's open file, at the other stream's position, with its mode,
  # its path and its class.
  def reopen_stream(other)
    Primitive.attr! :hidden
    check_open
    other.send(:check_open)
    return self if equal?(other)

    # flush_before_seek: what this stream read ahead goes back first, so
    # an offset that the two descriptors share is where its reader is.
    @writable ? write_pending : unread
    pos = tell_or_nil(other) if other.send(:mode_state)[1]
    other.send(:write_pending)
    adopt_mode(other.send(:mode_state))
    # The other stream's mode word, FMODE_SYNC with it.
    @sync = other.sync
    @pid = other.pid
    @lineno = other.send(:mode_state)[1] ? other.lineno : 0
    @path = other.path if other.path
    unless @fd == other.fileno
      dup_from(other.fileno, @path)
      if pos
        seek(pos)
        other.seek(pos)
      end
    end
    clear_buffer
    @eof = false
    Primitive.zr_exc_set_class(self, other.class)
  end

  # io_tell as io_reopen reads it: a stream with no position, as a pipe,
  # gives none, and the reopen does not seek.
  def tell_or_nil(io)
    Primitive.attr! :hidden
    io.pos
  rescue SystemCallError
    nil
  end

  # rb_cloexec_dup2: a descriptor above the standard three keeps
  # FD_CLOEXEC, which dup2(2) itself clears.
  def dup_from(fd, name)
    Primitive.attr! :hidden
    result = Primitive.zr_io_dup2(fd, @fd)
    raise SystemCallError.new(name, -result, +"rb_io_reopen") if result < 0
    return if @fd <= 2

    flags = Primitive.zr_io_fcntl(@fd, F_GETFD, 0)
    Primitive.zr_io_fcntl(@fd, F_SETFD, flags | FD_CLOEXEC) unless flags.negative?
  end

  # The mode and the conversions of a stream, which a reopen copies.
  def mode_state
    Primitive.attr! :hidden
    [@mode, @readable, @writable, @external, @internal, @binmode, @universal, @read_options, @write_options]
  end

  def adopt_mode(state)
    Primitive.attr! :hidden
    @mode, @readable, @writable, @external, @internal, @binmode, @universal, @read_options, @write_options = state
    @bom_written = false
  end

  def flush
    flushed
    self
  end

  # rb_io_flush, which Kernel#p calls as a function, not as a send.
  def flushed
    Primitive.attr! :hidden
    check_open
    write_pending
  end

  def fsync
    check_open
    write_pending
    result = Primitive.zr_io_fsync(@fd)
    raise SystemCallError.new(@path, -result) if result.negative?

    0
  end

  # Writes out every stream that contains buffered bytes. The end of the
  # program calls this. If a stream cannot take the bytes any more, the
  # program does not see the error.
  def self.flush_pending
    Primitive.attr! :hidden
    until PENDING.empty?
      io = PENDING.pop
      begin
        io.send(:write_pending)
      rescue SystemCallError, IOError
        # What the stream kept stays with it, and the end goes on.
        PENDING.delete(io)
      end
    end
    nil
  end

  # rb_stdio_set_default_encoding: as the program starts, the standard
  # streams take the default encodings that the command line set. With no
  # internal one they stay as they are: a stream that writes keeps none.
  def self.stdio_encodings
    Primitive.attr! :hidden
    internal = Encoding.default_internal or return
    external = Encoding.default_external
    [STDIN, STDOUT, STDERR].each { |io| io.set_encoding(external, internal == external ? nil : internal) }
    nil
  end

  # CRuby flushes the two standard streams before it starts a child, so
  # that the parent's buffered bytes cannot arrive after the child's output.
  def self.flush_std
    Primitive.attr! :hidden
    [$stdout, $stderr].each do |io|
      io.flush if io.is_a?(IO) && !io.closed?
    rescue SystemCallError, IOError
      nil
    end
    nil
  end

  # FMODE_BINMODE alone: no newline conversion, and the encodings stay.
  def binary_mode_flag
    Primitive.attr! :hidden
    @binmode = true
  end

  # Binary mode: all that is read after this is binary, and so are the
  # bytes already in the buffer.
  def binmode
    check_open
    @binmode = true
    # Binary mode sets the stream's encoding, whatever encoding it was
    # opened with, and drops the newline decorators (rb_io_binmode).
    @external = nil
    @internal = nil
    @universal = false
    @write_options&.delete(:newline)
    @buffer.force_encoding(Encoding::BINARY)
    self
  end

  def binmode?
    check_open
    @binmode
  end

  def fdatasync = fsync

  def to_path = path

  # A stream opened from a descriptor has no path behind it, so its
  # rows come from fstat(2).
  # rb_io_stat: fstat(2) on the descriptor, never the path, which can
  # name another file by now, or none (`<STDIN>`).
  def stat
    check_open
    File::Stat.for_fd(@fd)
  end

  # fcntl(2) on the stream's own descriptor: F_GETFD reads the
  # close-on-exec flag, F_GETFL the flags it was opened with, and a
  # command that takes a number takes it here too. rb_fcntl reads nil and
  # false as 0 and true as 1, and a String as the struct a command such
  # as a file lock reads and fills.
  def fcntl(command, argument = 0)
    check_open
    command = Numeric.send(:int_operand, command)
    result = if argument.is_a?(String)
               # rb_io_ctl: the String is the struct, written in place.
               raise FrozenError.new("can't modify frozen String: #{argument.inspect}", receiver: argument) if argument.frozen?

               Primitive.zr_io_fcntl_bytes(@fd, command, argument)
             else
               value = case argument
                       when nil, false then 0
                       when true then 1
                       else Numeric.send(:int_operand, argument)
                       end
               Primitive.zr_io_fcntl(@fd, command, value)
             end
    # rb_sys_fail_path gives the stream, and the call that set up the
    # argument, after the message; a stream with no path gives neither.
    raise SystemCallError.new(path, -result, +"finish_narg") if result < 0

    # rb_cloexec_fcntl_dupfd: a copy above the standard three closes on exec.
    if command == F_DUPFD && result > 2
      flags = Primitive.zr_io_fcntl(result, F_GETFD, 0)
      Primitive.zr_io_fcntl(result, F_SETFD, flags | FD_CLOEXEC) unless flags.negative?
    end
    result
  end

  # posix_fadvise is a hint, and darwin has none: ruby returns nil
  # where the call is absent.
  # rb_io_advise: the advice is a Symbol, and the two ends are off_t.
  def advise(kind, offset = 0, length = 0)
    raise TypeError, +"advice must be a Symbol" unless kind.is_a?(Symbol)

    IO.send(:offset_of, offset)
    IO.send(:offset_of, length)
    check_open
    raise NotImplementedError, "Unsupported advice: #{kind.inspect}" unless %i[normal sequential random willneed dontneed noreuse].include?(kind)

    nil
  end

  # Half-closing an end the stream does not have is an error; on one it
  # does have, and which is not duplex, it closes the whole stream.
  def close_read
    # rb_io_close_read: a closed stream has nothing left to close.
    return nil if closed?
    raise IOError, +"closing non-duplex IO for reading" if @mode.start_with?("w", "a") && !@mode.include?("+")
    return close unless @twin

    # A duplex handle's write end takes the stream's place, with the
    # child, and the stream writes on.
    clear_buffer
    result = Primitive.zr_io_close(@fd)
    @fd = @twin
    @twin = nil
    @readable = false
    raise SystemCallError.new(nil, -result) if result < 0

    nil
  end

  # A duplex handle really half-closes: the twin closes and the child
  # reads its end of input, while its output stays readable here.
  def close_write
    return nil if closed?
    raise IOError, +"closing non-duplex IO for writing" if @readable && !@twin && !@pid
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
  def pid
    check_open
    @pid
  end

  def autoclose?
    check_open
    @autoclose
  end

  def autoclose=(flag)
    check_open
    @autoclose = flag ? true : false
    own_descriptor
    flag
  end

  # FD_CLOEXEC on the descriptor, and on the twin that a duplex popen
  # writes to, as rb_io_close_on_exec_p reads both.
  F_DUPFD = 0
  F_GETFD = 1
  F_SETFD = 2
  FD_CLOEXEC = 1
  private_constant :F_DUPFD, :F_GETFD, :F_SETFD, :FD_CLOEXEC

  def close_on_exec?
    check_open
    [@fd, @twin].compact.all? { |fd| Primitive.zr_io_fcntl(fd, F_GETFD, 0) & FD_CLOEXEC != 0 }
  end

  def close_on_exec=(flag)
    check_open
    [@fd, @twin].compact.each do |fd|
      flags = Primitive.zr_io_fcntl(fd, F_GETFD, 0)
      raise SystemCallError.new(@path, -flags) if flags.negative?

      wanted = flag ? flags | FD_CLOEXEC : flags & ~FD_CLOEXEC
      next if wanted == flags

      result = Primitive.zr_io_fcntl(fd, F_SETFD, wanted)
      raise SystemCallError.new(@path, -result) if result.negative?
    end
    flag
  end

  # One character at a time, as rb_io_each_codepoint reads them: a byte
  # that starts no character is an error, not a code point.
  def each_codepoint
    return to_enum(:each_codepoint) unless block_given?

    check_readable
    while (char = transcoded(read_char))
      raise ArgumentError, "invalid byte sequence in #{char.encoding}" unless char.valid_encoding?

      yield char.ord
      # A block that closed the stream ends the walk.
      check_open
    end
    self
  end

  # `pread` and `pwrite` leave the descriptor's own offset alone.
  # pread(2) and pwrite(2) name a file position and leave the stream's
  # own where it was, buffer included.
  # rb_io_pread: the arguments convert first, and a length of 0 returns
  # the buffer as it is, or an empty String, before the IO is checked.
  def pread(length, offset, buffer = nil)
    length = Primitive.zr_index_operand_m(length)
    offset = Primitive.zr_index_operand_m(offset)
    raise ArgumentError, +"negative string size (or size too big)" if length.negative?

    buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
    return buffer || +"".b if length.zero?

    check_readable
    IO.send(:room_for!, length)
    text = if (scheduler = IO.send(:scheduler_taking, :io_pread))
             IO::Buffer.send(:lent, "\0".b * length) do |memory|
               read = IO.send(:io_result, scheduler.io_pread(self, memory, offset, 0, 0))
               read.positive? ? memory.get_string(0, read) : (read.zero? ? nil : read)
             end
           else
             Primitive.zr_io_pread(@fd, length, offset)
           end
    raise SystemCallError.new(label, -text, +"rb_io_pread") if text.is_a?(Integer)

    filled(text&.force_encoding(Encoding::BINARY), buffer)
  end

  def pwrite(text, offset)
    text = Primitive.zr_obj_as_string(text)
    offset = IO.send(:offset_of, offset)
    check_writable
    result = if (scheduler = IO.send(:scheduler_taking, :io_pwrite))
               IO::Buffer.send(:lent, text.b, readonly: true) do |memory|
                 IO.send(:io_result, scheduler.io_pwrite(self, memory, offset, 0, 0))
               end
             else
               Primitive.zr_io_pwrite(@fd, text, offset)
             end
    raise SystemCallError.new(label, -result, +"rb_io_pwrite") if result < 0

    result
  end

  # The offset where the seek lands, as lseek returns it.
  def sysseek(offset, whence = SEEK_SET)
    offset = IO.send(:offset_of, offset)
    check_open
    raise IOError, +"sysseek for buffered IO" unless @buffer.empty?

    Primitive.zr_warn_here_m("sysseek for buffered IO") unless @wbuf.empty?
    seek(offset, whence)
    pos
  end

  # The encoding given for this stream, else the default for its kind:
  # binary where it is binary, the default where it can be read,
  # and none at all for a handle that only writes.
  def external_encoding
    return @external unless @external.nil?
    return Encoding::BINARY if @binmode
    # A stream that writes and reads returns nil until something sets
    # its encoding, because rb_io_external_encoding checks whether the
    # stream is writable rather than write-only.
    return nil unless @readable && !@writable

    Encoding.default_external
  end

  def internal_encoding = @internal

  # io_encoding_set: two encodings, one encoding or spec string, or nil
  # for the defaults. A spec string warns where a name matches nothing;
  # an encoding given alone must exist.
  def set_encoding(external, internal = (one = true; nil), **options)
    check_open
    if !one && !internal.nil?
      from = IO.send(:found_encoding, external)
      to = String.try_convert(internal) == +"-" ? from : IO.send(:found_encoding, internal)
      # With no conversion, the stream reads in the second encoding.
      from = nil if to.equal?(from)
      from, to = nil, from if Encoding::BINARY.equal?(from)
      # A conversion to a name that matched nothing reads as the default
      # external encoding, as io_read_encoding falls back.
      to ||= Encoding.default_external unless from.nil?
      external, internal = from.nil? ? [to, nil] : [from, to]
    elsif external.nil?
      external, internal = IO.send(:default_encodings, nil)
      # A binary stream drops its BINARY too: it reads in the default
      # external encoding, as io_read_encoding gives with none set.
      external ||= Encoding.default_external if @binmode
    elsif (text = String.try_convert(external)) && text.encoding.ascii_compatible?
      external, internal, = IO.send(:mode_encodings, text)
      external, internal = IO.send(:default_encodings, external) if internal.nil? && !external.nil?
    else
      external, internal = IO.send(:default_encodings, IO.send(:found_encoding, external))
    end
    options = {} if !one && internal.nil? && options.empty?
    conversion = IO.send(:conversion_options, options, @universal)
    IO.send(:check_binmode, @readable, @binmode, external, internal, conversion)
    @external = external
    @internal = internal
    converting(conversion)
    # What is already buffered reads as the new encoding too.
    @buffer.force_encoding(read_encoding)
    # Only an open mode reads a BOM: set_encoding takes `bom|` off the name
    # and reads nothing, as io_encoding_set does.
    self
  end

  # rb_io_inspect: the path, or the descriptor, which a closed stream no
  # longer has; a stream with no descriptor at all is any object.
  def inspect
    return "#{Primitive.zr_obj_head(self)}>" if @fd.nil?

    shown = @name || @path
    text = if shown then @closed ? "#{shown} (closed)" : shown
           else @closed ? +"(closed)" : "fd #{@fd}"
           end
    Primitive.zr_obj_form("#<#{self.class}:#{text}>")
  end

  # The arguments are walked without Array's own methods: a program
  # that redefines one of those must not break the stream it writes
  # the redefinition's report to.
  # io_write: one empty String writes nothing, and checks nothing.
  def write(*objects)
    if Primitive.zr_ary_len_m(objects) == 1
      text = Primitive.zr_obj_as_string(Primitive.zr_ary_at_m(objects, 0))
      # io_write: an empty write needs a stream that was initialized, not
      # one that is still open.
      if text.empty?
        check_initialized
        return 0
      end

      check_writable
      return write_bytes(converted(text))
    end
    check_writable
    total = 0
    i = 0
    while i < Primitive.zr_ary_len_m(objects)
      total += write_bytes(converted(Primitive.zr_obj_as_string(Primitive.zr_ary_at_m(objects, i))))
      i += 1
    end
    total
  end

  # do_writeconv: the bytes that a write puts out. `xml: :attr` quotes
  # the stream as a whole, as make_writeconv's converter keeps the quote
  # as its state: each write's own quotes go, the first bytes open the
  # stream's quote, and the close ends it (finish_writing). A converter
  # that keeps state across writes quotes the stream itself.
  def converted(text)
    Primitive.attr! :hidden
    out = encoded(text)
    return out unless @write_options[:xml] == :attr && @write_converter.nil?

    quote = Primitive.zr_str_bytesize("\"".encode(out.encoding))
    body = out.byteslice(quote, out.bytesize - (2 * quote))
    return body if body.empty? || @xml_quote

    @xml_quote = out.byteslice(0, quote)
    @xml_quote + body
  end

  # What is written goes out in the external encoding the stream names,
  # unless that is binary. An encoding that is not ASCII-compatible is
  # reached through UTF-8, as the converter make_writeconv sets up
  # reaches it.
  def encoded(text)
    Primitive.attr! :hidden
    options = @write_options
    source = Encoding.at(Primitive.zr_str_encoding_index_m(text))
    target = @external.nil? || @external == Encoding::BINARY ? nil : @external
    # With nothing to convert to, only the decorators change the text.
    if target.nil? || source == target
      decorators = options.slice(:newline, :xml)
      return decorators.empty? ? text : text.encode(source, source, **decorators)
    end
    return text.encode(target, **options) if target.ascii_compatible?

    # The hop to UTF-8 only handles errors; the decorators work once, on
    # the way to the target.
    text = text.encode(Encoding::UTF_8, **options.slice(:invalid, :undef, :replace)) unless source == Encoding::UTF_8
    return stateful_converted(text, target, options) if stateful?(target)

    once_marked(text.encode(target, **options))
  end

  # An encoding with shift states, such as ISO-2022-JP, whose converter
  # writes an escape to end the stream.
  def stateful?(encoding)
    Primitive.attr! :hidden
    encoding.name.start_with?("ISO-2022-JP", "CP5022", "stateless-ISO-2022-JP")
  end

  # make_writeconv's double conversion for a stateful encoding: each
  # write goes first into the encoding's ASCII-compatible form with every
  # option but the quote, then through one converter that keeps the shift
  # state, and the quote of xml: :attr, from one write to the next. The
  # close writes that converter's finish.
  def stateful_converted(text, target, options)
    Primitive.attr! :hidden
    common = Encoding::Converter.asciicompat_encoding(target)
    attr = options[:xml] == :attr
    @write_converter ||= Encoding::Converter.new(common, target, attr ? Encoding::Converter::XML_ATTR_QUOTE_DECORATOR : 0)
    text = text.encode(common, **options)
    text = text.byteslice(1, text.bytesize - 2) if attr
    out = +""
    result = @write_converter.primitive_convert(text, out, nil, nil, partial_input: true)
    raise @write_converter.last_error unless result == :source_buffer_empty

    out
  end

  # finish_writeconv: the bytes that end the stream: the closing quote of
  # an xml: :attr stream, or a stateful encoding's shift back.
  def finish_writing
    Primitive.attr! :hidden
    if @xml_quote
      write_bytes(@xml_quote)
      @xml_quote = nil
    end
    converter = @write_converter or return
    @write_converter = nil
    tail = converter.finish
    write_bytes(tail) unless tail.empty?
  end

  # A dummy UTF-16 or UTF-32 target writes a byte order mark before each
  # String; the stream keeps only the first one.
  def once_marked(text)
    Primitive.attr! :hidden
    return text unless @external.dummy? && !text.empty?

    mark = @external.name == +"UTF-16" ? 2 : 4
    return text.byteslice(mark, text.bytesize - mark) if @bom_written

    @bom_written = true
    text
  end

  # rb_io_syswrite: writes the bytes directly to the descriptor, past
  # the buffer. Ruby warns if the buffer still contains bytes.
  def syswrite(text)
    check_writable
    text = Primitive.zr_obj_as_string(text)
    Primitive.zr_warn_here_m("syswrite for buffered IO") unless @wbuf.empty?
    # A descriptor that cannot wait gets one write(2), which can take
    # only part of the text, as rb_io_syswrite makes it.
    if @nonblock && !IO.send(:scheduler_taking, :io_write)
      return checked_write(Primitive.zr_io_write_some(@twin || @fd, text.b, 0, text.bytesize))
    end

    write_now(text.b)
  end

  def <<(object)
    write(object)
    self
  end

  # `$,` goes between the objects and `$\` after the last one, which is
  # what makes `print` and `puts` differ.
  def print(*objects) = IO.print_to(self, objects)

  # One String, the usual call, is its own line: CRuby takes a String
  # as it is and never calls `to_s` on it.
  # One String is the common call: its bytes, then a newline unless it
  # ends in one, with no line walk between.
  def puts(*objects)
    # A `write` that the program wrote gets every piece, as CRuby's
    # rb_io_writev sends it; the core's own writes the bytes here.
    unless Primitive.zr_basic_method_m(self, :write)
      IO.each_line_of(objects) { |*parts| IO.writev(self, parts) }
      return nil
    end
    if Primitive.zr_ary_len_m(objects) == 1 && (text = Primitive.zr_ary_at_m(objects, 0)).is_a?(String)
      check_writable
      write_bytes(converted(text))
      write_bytes(converted(NEWLINE)) unless IO.send(:ends_line?, text)
      return nil
    end
    IO.each_line_of(objects) { |*parts| write(*parts) }
    nil
  end

  # rb_io_writev: the pieces in one `write`, or one `write` each when the
  # method takes one argument (with a deprecation warning under
  # $VERBOSE, except for $stderr).
  def self.writev(out, parts)
    Primitive.attr! :hidden
    return out.write(*parts) unless parts.size > 1 && out.method(:write).arity == 1

    warn("#{out.class.inspect}#write is outdated interface which accepts just one argument", category: :deprecated) if $VERBOSE && !out.equal?($stderr)
    parts.each { |part| out.write(part) }
    nil
  end

  # What `puts` writes for `objects`, one `write` a line, as it goes: a
  # line that raises in its `to_s` stops the rest, with what came before
  # already written, as ruby's does. Each one's to_s, then a newline as a
  # second argument unless it ends in one; nil is an empty line; an Array
  # is its items, an empty one nothing; no objects is one empty line.
  # rb_str_end_with_asciichar(text, "\n"): whether the last character is
  # a newline, read in the text's own encoding. In a wide encoding the
  # last code unit holds it, and a newline byte inside a wider character
  # is no newline.
  def self.ends_line?(text)
    Primitive.attr! :hidden
    size = Primitive.zr_str_bytesize(text)
    return false if size.zero?

    unit, at = WIDE_UNITS[Encoding.at(Primitive.zr_str_encoding_index_m(text)).name]
    return Primitive.zr_str_byte_at(text, size - 1) == 10 if unit.nil?
    return false if size % unit != 0

    start = size - unit
    (0...unit).all? { |i| Primitive.zr_str_byte_at(text, start + i) == (i == at ? 10 : 0) }
  end
  private_class_method :ends_line?

  def self.each_line_of(objects, &block)
    Primitive.attr! :hidden
    return yield(+"\n") if objects.empty?

    objects.each do |object|
      # A String is a line as it is. Anything else marks the walk before
      # its #to_ary runs (rb_exec_recursive), so an object whose items
      # contain it shows the marker in its own place, and the walk does
      # not go on for ever.
      unless String === object
        next yield(+"[...]", +"\n") if Primitive.zr_recursive_enter(object, :puts)

        begin
          # rb_check_array_type: an object that converts is its items.
          items = Array.try_convert(object)
          each_line_of(items, &block) unless items.nil? || items.empty?
        ensure
          Primitive.zr_recursive_leave(object, :puts)
        end
        next if items
      end
      text = Primitive.zr_obj_as_string(object)
      if text.empty?
        yield(+"\n")
      elsif ends_line?(text)
        yield text
      else
        yield text, +"\n"
      end
    end
  end

  # What `print` writes `objects` as: their `to_s` joined by `$,`, then
  # `$\`, and `$_` where there are no objects.
  #
  # One `write` per object, with the object as it is: `write` calls its
  # `to_s`, so an object whose `to_s` raises stops the rest after what came before.
  # Each object's inspect (or each line, `inspect` false) on its own
  # line, then a flush, as `p` writes.
  def self.p_to(out, objects, inspect)
    Primitive.attr! :hidden
    i = 0
    while i < Primitive.zr_ary_len_m(objects)
      line = Primitive.zr_ary_at_m(objects, i)
      # rb_p writes rb_inspect of each object.
      out.write(inspect ? Primitive.zr_inspect(line) : line, "\n")
      i += 1
    end
    out.send(:flushed) if out.is_a?(IO)
  end
  private_class_method :p_to

  def self.print_to(out, objects)
    Primitive.attr! :hidden
    objects = [$_] if objects.empty?
    first = true
    objects.each do |object|
      out.write($,) if $, && !first
      out.write(object)
      first = false
    end
    out.write($\) if $\
    nil
  end

  def printf(*args)
    write(Kernel.format(*args))
    nil
  end

  # `read(length)`: that many bytes, fewer at the end, nil past it, and
  # always binary; without a length, everything that is left.
  # The length is checked before the stream, as io_read does.
  def read(length = nil, buffer = nil)
    length = Primitive.zr_index_operand_m(length) unless length.nil?
    raise ArgumentError, "negative length #{length} given" if length && length < 0

    buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
    check_readable
    # io_read: a read of a length takes bytes.
    check_byte_readable if length

    IO.send(:room_for!, length)
    # A scheduler's io_read gets the same byte count that io.c requests.
    scheduled = IO.send(:scheduler_taking, :io_read)
    if length.nil?
      if scheduled
        text = read_all.force_encoding(fresh_buffer.encoding)
      else
        fill_cooked until @eof
        text = @buffer
      end
      # A conversion that stops pushes back what follows the bad byte.
      clear_buffer
      out = transcoded(text)
    else
      if scheduled
        text = bufread(length)
        return buffer&.clear && nil if text.empty? && length > 0

        return filled(text, buffer)
      end
      # io_bufread: what the buffer holds, then the rest with no buffer.
      text = take([length, @buffer.bytesize].min).force_encoding(Encoding::BINARY)
      text << locking(buffer) { read_direct(length - text.bytesize) } if text.bytesize < length
      # At the end, the buffer is emptied, as io_read does.
      return buffer&.clear && nil if text.empty? && length > 0

      return filled(text, buffer)
    end
    buffer ? buffer.replace(out) : out
  end

  # Up to `length` bytes past the buffer, read until they are all there
  # or the stream ends.
  def read_direct(length)
    Primitive.attr! :hidden
    text = +"".b
    while text.bytesize < length
      park_to_read
      chunk = read_memory(length - text.bytesize)
      break if chunk.nil?

      if chunk.is_a?(Integer)
        raise SystemCallError.new(label, -chunk, +"io_fread") unless -chunk == Errno::EAGAIN::Errno

        wait_again(READABLE)
      else
        text << chunk.b
      end
    end
    text
  end

  # These three all read what is there and fill a buffer when one is
  # given; the end of the stream is an error, not a nil.
  # rb_io_sysread: one read(2) of the descriptor, past the buffer, which
  # must be empty.
  def sysread(length, buffer = nil)
    length = Primitive.zr_index_operand_m(length)
    raise ArgumentError, "negative length #{length} given" if length < 0

    buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
    return buffer || +"".b if length.zero?

    check_readable
    check_byte_readable
    raise IOError, +"sysread for buffered IO" unless @buffer.empty?

    IO.send(:room_for!, length)
    chunk = locking(buffer) do
      park_to_read unless IO.send(:scheduler_taking, :io_read)
      loop do
        chunk = read_memory(length)
        break chunk unless chunk.is_a?(Integer)
        raise SystemCallError.new(label, -chunk, +"sysread") unless -chunk == Errno::EAGAIN::Errno

        wait_again(READABLE)
      end
    end
    filled(chunk&.b, buffer)
  end

  def readpartial(length, buffer = nil)
    # io_setstrbuf: the buffer converts before the stream is read.
    buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
    check_byte_readable
    filled(locking(buffer) { read_some(length) }, buffer)
  end

  # CRuby writes these three in Ruby (its io.rb), so they return their
  # own parameters, under CRuby's names.
  def read_nonblock(len, buf = nil, exception: true)
    Primitive.attr! :ruby
    exception = exception_flag(exception)
    raise ArgumentError, "negative length #{len} given" if len < 0

    check_readable
    check_byte_readable
    set_nonblock(true) unless nonblock_flag?
    if !buffered? && !len.zero? && would_block?(READABLE)
      return :wait_readable unless exception

      raise EAGAINWaitReadable, +"read would block"
    end
    text = read_some(len)
    return buf&.clear && nil if text.nil? && !exception

    filled(text, buf)
  end

  def write_nonblock(buf, exception: true)
    Primitive.attr! :ruby
    exception = exception_flag(exception)
    check_writable
    set_nonblock(true) unless nonblock_flag?
    text = buf.is_a?(String) ? buf : buf.to_s
    if would_block?(WRITABLE)
      return :wait_writable unless exception

      raise EAGAINWaitWritable, +"write would block"
    end
    # What waits in the buffer goes first, so the bytes keep their order.
    write_pending
    wrote = Primitive.zr_io_write_some(@twin || @fd, text, 0, text.bytesize)
    if wrote < 0 && -wrote == Errno::EAGAIN::Errno
      return :wait_writable unless exception

      raise EAGAINWaitWritable, +"write would block"
    end
    checked_write(wrote)
  end

  # rb_io_putc: a String's first character, or the byte NUM2CHR makes of
  # anything else.
  def putc(c)
    write(c.is_a?(String) ? c[0, 1] : (IO.send(:c_int, c) & 0xff).chr)
    c
  end

  # The byte that setup_narg writes after a buffer, which the result must
  # not change, and the mask that reads a command's own length.
  IOCTL_SENTINEL = 17
  IOCPARM_MASK = 0x1fff
  private_constant :IOCTL_SENTINEL, :IOCPARM_MASK

  # ioctl(2). rb_io_ctl reads the argument as setup_narg does: nil and
  # false are 0, true is 1, an Integer represents itself, and a String is
  # the buffer that the command fills. The buffer grows to the length in
  # the command, with one byte after it that the result must not reach.
  def ioctl(command, argument = 0)
    check_open
    command = Numeric.send(:int_operand, command)
    buffer = ioctl_buffer(command, argument)
    result = if buffer.nil?
               Primitive.zr_io_ioctl(@fd, command, ioctl_narg(argument))
             else
               Primitive.zr_io_ioctl_buf(@fd, command, buffer)
             end
    raise SystemCallError.new(path, -result, +"finish_narg") if result < 0
    return result if buffer.nil?

    # finish_narg: the sentinel says the command wrote no further than
    # the room the buffer gave it.
    raise ArgumentError, +"return value overflowed string" unless buffer.getbyte(buffer.bytesize - 1) == IOCTL_SENTINEL

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

  # A byte order mark at the head of the stream gives the encoding.
  # rb_io_set_encoding_by_bom: a binary stream with no encoding of its
  # own takes the one its byte order mark gives.
  def set_encoding_by_bom
    check_open
    raise ArgumentError, +"ASCII incompatible encoding needs binmode" unless @binmode
    raise ArgumentError, +"encoding conversion is set" unless @internal.nil?
    raise ArgumentError, "encoding is set to #{@external} already" unless @external.nil? || Encoding::BINARY.equal?(@external)
    # io_strip_bom: a stream that cannot read has no mark to find.
    return nil unless @readable

    strip_bom
  end

  # io_strip_bom and io_set_encoding_by_bom: the byte order mark at the
  # head of the stream goes, and names the external encoding.
  def strip_bom
    Primitive.attr! :hidden
    fill while !@eof && @buffer.bytesize < 4
    head = @buffer.b
    mark, name = BOMS.find { |bytes, _| head.start_with?(bytes) }
    if mark.nil?
      # With no mark, the stream reads in the encoding it would have
      # converted to, as io_set_encoding_by_bom clears enc2.
      @external, @internal = @internal, nil unless @internal.nil?
      @buffer.force_encoding(read_encoding)
      return nil
    end
    take(mark.bytesize)
    @external = Encoding.find(name)
    @internal = nil if @internal.equal?(@external)
    if decoding?
      # The bytes after the mark are raw: they convert as a fill would.
      raw = @buffer.b
      clear_buffer
      @buffer << decoded(raw).force_encoding(@buffer.encoding)
    end
    @buffer.force_encoding(read_encoding)
    @external
  end


  # One character in the read encoding, in the internal one when the
  # stream has one.
  def getc
    check_readable
    transcoded(read_char)
  end

  def readchar = getc || raise(EOFError, +"end of file reached")

  def getbyte = read(1)&.getbyte(0)

  def readbyte = getbyte || raise(EOFError, +"end of file reached")

  # rb_io_ungetc: an Integer is a code point in the read encoding, as an
  # unsigned int; anything else must convert to a String. Either way its
  # bytes go back in front of the buffer.
  def ungetc(text)
    check_readable
    text = if text.is_a?(Integer)
             ungot_code(text).chr(read_encoding)
           else
             Primitive.zr_str_operand(text)
           end
    push_back(text)
    @char_front += text.bytesize
    nil
  end

  # rb_io_ungetbyte: nil puts back nothing, and an Integer is one byte,
  # modulo 256.
  def ungetbyte(byte)
    check_readable
    check_byte_readable
    return nil if byte.nil?

    push_back(byte.is_a?(Integer) ? (byte % 256).chr : Primitive.zr_str_operand(byte))
  end

  # A line up to and with `separator`; "" separates paragraphs; nil
  # reads to the end. `limit` caps the bytes.
  def gets(*args, chomp: false)
    check_readable
    separator, limit = getline_args(args)
    separator = stream_separator(separator)
    # A zero limit reads nothing and counts no line, as rb_io_getline_0
    # returns before it touches the stream.
    return $_ = fresh_buffer if limit == 0

    line = transcoded(read_line(separator, limit))
    $_ = nil
    return nil if line.nil?

    unless @cut
      @lineno += 1
      $. = @lineno
    end
    $_ = chomp ? chomp_line(line, separator) : line
  end

  def readline(sep = (nosep = true), limit = (nolimit = true), chomp: false)
    Primitive.attr! :ruby
    args = nosep ? [] : (nolimit ? [sep] : [sep, limit])
    gets(*args, chomp: chomp) || raise(EOFError, +"end of file reached")
  end

  # Each line as `gets` reads it, counted in `$.`; `$_` is `gets`'s
  # alone, as rb_io_each_line leaves it.
  def each_line(*args, chomp: (bare = true; false), &block)
    return to_enum(__callee__, *args, **(bare ? {} : { chomp: chomp })) unless block

    each_line_for(:each_line, args, chomp, &block)
  end

  alias each each_line

  # Keywords other than chomp: do not count, as extract_getline_opts reads only that one.
  def readlines(*args, chomp: false, **)
    lines = []
    each_line_for(:readlines, args, chomp) { |line| lines << line }
    lines
  end

  # Each line as `gets` reads it, for the method `name`, which a zero
  # limit's error names.
  def each_line_for(name, args, chomp)
    Primitive.attr! :hidden
    check_readable
    separator, limit = getline_args(args)
    raise ArgumentError, "invalid limit: 0 for #{name}" if limit == 0

    separator = stream_separator(separator)

    while (line = transcoded(read_line(separator, limit)))
      unless @cut
        @lineno += 1
        $. = @lineno
      end
      yield chomp ? chomp_line(line, separator) : line
    end
    self
  end

  def each_char
    return to_enum(:each_char) unless block_given?

    check_readable
    while (char = transcoded(read_char))
      yield char
      check_open
    end
    self
  end

  def each_byte
    return to_enum(:each_byte) unless block_given?

    check_byte_readable
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
    raise SystemCallError.new(label, -result, +"rb_io_tell") if result < 0

    result - @buffer.bytesize
  end

  alias tell pos

  def seek(offset, whence = SEEK_SET)
    offset = IO.send(:offset_of, offset)
    check_open
    write_pending
    whence = IO.send(:whence_of, whence)
    offset -= @buffer.bytesize if whence == SEEK_CUR
    clear_buffer
    @eof = false
    result = Primitive.zr_io_seek(@fd, offset, whence)
    raise SystemCallError.new(label, -result, +"rb_io_seek") if result < 0

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
    own_descriptor
  end

  # Points the stream's Closer at its descriptor while the stream owns it
  # and has it open, and at none otherwise. The first descriptor that the
  # stream owns registers the Closer as a finalizer.
  def own_descriptor
    Primitive.attr! :hidden
    owned = @autoclose && !@closed ? @fd : nil
    if @closer
      @closer.fd = owned
    elsif owned
      @closer = Closer.new(owned)
      (Primitive.zr_finalizers_m[self] ||= [__id__]) << @closer
    end
  end

  # rb_io_check_closed: an allocated stream has no descriptor to check.
  def check_open
    Primitive.attr! :hidden
    check_initialized
    raise IOError, +"closed stream" if @closed
  end

  # rb_io_check_initialized: a stream that IO.allocate made and no
  # initialize has opened.
  def check_initialized
    Primitive.attr! :hidden
    raise IOError, +"uninitialized stream" if @fd.nil?
  end

  # The wait before a read(2). A listening socket (the socket library
  # marks it) reads nothing: read(2) fails at once with ENOTCONN, so no
  # wait comes first. Net::FTP reads its listener after it accepts.
  def park_to_read
    Primitive.attr! :hidden
    park_until(READABLE) unless Primitive.zr_hidden_get(self, :__listening__)
  end

  # A system call on a descriptor that is not ready would stop every
  # green thread. So a task that shares the process with others yields
  # to the scheduler until the descriptor is ready. A single task waits
  # in the system call itself, or in poll(2) when the descriptor cannot wait.
  def park_until(event, fd = @fd)
    Primitive.attr! :hidden
    # rb_io_wait: a non-blocking fiber hands a descriptor that is not
    # ready to its scheduler.
    if (scheduler = Fiber.current_scheduler)
      return if Primitive.zr_io_wait(fd, event, 0) != 0

      return scheduler.io_wait(self, event, @timeout)
    end
    return unless @nonblock || (Primitive.zr_threaded && !Thread.send(:alone?))

    Thread.current.send(:wait_io, fd, event, nil)
  end

  # Whether a call on this descriptor would wait. A non-blocking call
  # checks this first and then makes the ordinary call, which returns
  # immediately on a ready descriptor.
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
    raise SystemCallError.new(label, -answer, +"set_nonblock") unless answer.zero?

    @nonblock = on
  end

  # The flag as the descriptor itself has it. Another process or an
  # accepted socket can have set it.
  def nonblock_flag?
    Primitive.attr! :hidden
    flags = Primitive.zr_io_flags(@fd)
    flags >= 0 && (flags & O_NONBLOCK) != 0
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
      Primitive.zr_str_cat_bytes(@wbuf, text)
      return text.bytesize
    end
    # A scheduler's io_write takes the waiting bytes, then the text,
    # because io_binwrite's writev gives it only the first of the two.
    if IO.send(:scheduler_taking, :io_write)
      write_pending
      return write_now(text)
    end
    # The buffer is bytes, whatever encoding the text is in.
    held = @wbuf.bytesize
    waiting = Primitive.zr_str_cat_bytes(@wbuf, text)
    @wbuf = +"".b
    PENDING.delete(self)
    write_now(waiting) - held
  end

  # The fiber scheduler's memory hooks, as scheduler.c lends them the
  # bytes: the scheduler of a non-blocking fiber, where it takes `hook`.
  def self.scheduler_taking(hook)
    Primitive.attr! :hidden
    scheduler = Fiber.current_scheduler
    scheduler if scheduler.respond_to?(hook)
  end

  # rb_fiber_scheduler_io_result_apply: a count, or the negative errno.
  def self.io_result(result)
    Primitive.attr! :hidden
    result.is_a?(Integer) ? result : Integer(result.to_int)
  end
  private_class_method :scheduler_taking, :io_result

  # rb_io_read_memory: at most `size` bytes, which a scheduler's io_read
  # reads into a buffer lent it; a String, nil at the end, or the
  # negative errno.
  def read_memory(size)
    Primitive.attr! :hidden
    scheduler = IO.send(:scheduler_taking, :io_read)
    return Primitive.zr_io_read(@fd, size) unless scheduler

    IO::Buffer.send(:lent, "\0".b * size) do |memory|
      read = IO.send(:io_result, scheduler.io_read(self, memory, 0, 0))
      next read if read.negative?

      read.zero? ? nil : memory.get_string(0, read)
    end
  end

  # io_binwrite_string over a scheduler's io_write: the rest of the
  # bytes lent it again until it has taken them all, waiting where it
  # says the descriptor is not ready.
  def scheduled_write(text)
    Primitive.attr! :hidden
    scheduler = IO.send(:scheduler_taking, :io_write)
    text = text.b
    from = 0
    while from < text.bytesize
      rest = text.byteslice(from, text.bytesize - from)
      wrote = IO::Buffer.send(:lent, rest, readonly: true) do |memory|
        IO.send(:io_result, scheduler.io_write(self, memory, 0, 0))
      end
      if wrote.negative?
        raise SystemCallError.new(label, -wrote, +"rb_sys_fail_on_write") unless -wrote == Errno::EAGAIN::Errno

        wait_again(WRITABLE)
      else
        from += wrote
      end
    end
    text.bytesize
  end

  # fptr_wait_readable and its writable twin: a call that said "not yet"
  # waits for the descriptor, in the scheduler where the fiber has one,
  # before it comes round again.
  def wait_again(event)
    Primitive.attr! :hidden
    scheduler = Fiber.current_scheduler
    scheduler ? scheduler.io_wait(self, event, @timeout) : Thread.pass
  end

  # io_bufread: `length` bytes, or fewer at the end. With nothing buffered
  # they come directly from the descriptor, with as many reads as necessary.
  # Otherwise the buffer gives out its bytes and fills again.
  def bufread(length)
    Primitive.attr! :hidden
    out = +"".b
    if @buffer.empty?
      while out.bytesize < length
        chunk = read_memory(length - out.bytesize)
        break if chunk.nil?

        if chunk.is_a?(Integer)
          raise SystemCallError.new(label, -chunk, +"io_fread") unless -chunk == Errno::EAGAIN::Errno

          wait_again(READABLE)
        else
          out << chunk
        end
      end
      return out
    end
    until out.bytesize >= length
      out << take([length - out.bytesize, @buffer.bytesize].min).b
      break if out.bytesize >= length

      fill
      break if @buffer.empty?
    end
    out
  end

  # read_all: what remains of a regular file, or BUFSIZ more at a time
  # of anything else, until a read comes up short.
  def read_all
    Primitive.attr! :hidden
    out = +"".b
    wanted = remain_size
    wanted = BUFSIZ if wanted.zero?
    loop do
      out << bufread(wanted - out.bytesize)
      break if out.bytesize < wanted

      wanted += BUFSIZ
    end
    out
  end

  BUFSIZ = 1024
  private_constant :BUFSIZ

  # remain_size: the bytes buffered, and past them the rest of a regular
  # file, or BUFSIZ where the stream has no end to measure.
  def remain_size
    Primitive.attr! :hidden
    held = @buffer.bytesize
    stat = File::Stat.for_fd(@fd)
    return held + BUFSIZ unless stat.file?

    write_pending
    at = Primitive.zr_io_seek(@fd, 0, SEEK_CUR)
    at >= 0 && stat.size >= at ? held + stat.size - at : held
  end

  # The descriptor a write goes to: the twin of a duplex stream.
  def write_descriptor
    Primitive.attr! :hidden
    @twin || @fd
  end

  # Writes out the bytes in the buffer.
  def write_pending
    Primitive.attr! :hidden
    return nil if @wbuf.empty?

    waiting = @wbuf
    @wbuf = +"".b
    PENDING.delete(self)
    write_now(waiting)
    nil
  rescue SystemCallError
    # io_fflush keeps what it could not write for the next flush.
    @wbuf = waiting << @wbuf
    PENDING << self unless Primitive.zr_table_member_p(PENDING, self)
    raise
  end

  def write_now(text)
    Primitive.attr! :hidden
    return scheduled_write(text) if IO.send(:scheduler_taking, :io_write)

    fd = @twin || @fd
    alone = !Primitive.zr_threaded || Thread.send(:alone?)
    return checked_write(Primitive.zr_io_write(fd, text)) if !@nonblock && alone && !Fiber.current_scheduler

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
    return result unless result.negative?

    error = SystemCallError.new(label, -result, +"rb_sys_fail_on_write")
    # rb_sys_fail_on_write: a closed pipe on standard output or error
    # carries SIGPIPE, so a program that does not rescue it ends by that
    # signal, quietly, as with no handler for it.
    Primitive.zr_hidden_set(error, :__signo__, 13) if -result == Errno::EPIPE::Errno && (@fd == 1 || @fd == 2)
    raise error
  end

  # The result of a read, into `buffer` when one was given. The end of
  # the stream is an error here, not a nil.
  # What one read(2) gives: the bytes already in the buffer, else one
  # fill of it. A partial read never waits for the whole length, so a
  # reader of a pipe returns as soon as any bytes arrive.
  def read_some(length)
    Primitive.attr! :hidden
    raise ArgumentError, "negative length #{length} given" if length < 0

    check_readable
    return "".b if length.zero?

    IO.send(:room_for!, length)

    # io_getpartial: with nothing buffered, one read of the requested
    # length, so a datagram socket loses the rest of its message as it
    # does in ruby. A scheduler's io_read takes the read.
    if @buffer.empty?
      return nil if @eof

      loop do
        park_to_read unless IO.send(:scheduler_taking, :io_read)
        chunk = read_memory(length)
        return chunk&.b unless chunk.is_a?(Integer)

        raise SystemCallError.new(label, -chunk, +"io_getpartial") unless -chunk == Errno::EAGAIN::Errno

        wait_again(READABLE)
      end
    end

    take([length, @buffer.bytesize].min).force_encoding(Encoding::BINARY)
  end

  # rb_str_locktmp_ensure: while a read waits to fill the caller's
  # buffer, the String is locked, so another thread that changes it
  # raises. The buffer must be one that can change (io_setstrbuf).
  def locking(buffer)
    Primitive.attr! :hidden
    return yield if buffer.nil?

    Primitive.zr_frozen_error(buffer) if Primitive.zr_modify_frozen_m(buffer)
    Primitive.zr_str_locktmp_m(buffer)
    begin
      yield
    ensure
      Primitive.zr_str_unlocktmp_m(buffer)
    end
  end

  # The bytes a read took, in the caller's buffer where there is one,
  # which keeps its own encoding.
  def filled(text, buffer)
    Primitive.attr! :hidden
    if text.nil?
      buffer&.clear
      raise EOFError, +"end of file reached"
    end
    return text unless buffer

    encoding = buffer.encoding
    buffer.replace(text).force_encoding(encoding)
  end

  # rb_io_check_char_readable: bytes that wait to be written go out
  # before a read.
  def check_readable
    Primitive.attr! :hidden
    check_open
    raise IOError, +"not opened for reading" unless @readable

    write_pending unless @wbuf.empty?
  end

  # rb_io_check_writable: a write after a buffered read goes where the
  # reader is.
  def check_writable
    Primitive.attr! :hidden
    check_open
    raise IOError, +"not opened for writing" unless @writable

    # A write takes the stream's write lock, which is a blocking point.
    Thread.send(:blocking_point)
    unread
  end

  # io_unread: the bytes read ahead go back to the file, so its offset is
  # where the reader is. A pipe cannot seek, and keeps them.
  def unread
    Primitive.attr! :hidden
    return if @buffer.empty? || @universal

    clear_buffer unless Primitive.zr_io_seek(@fd, -@buffer.bytesize, SEEK_CUR).negative?
  end

  # CRuby's read buffer has a fixed size, set as it is first made: 8192
  # bytes (IO_RBUF_CAPA_MIN), 128 KiB for a stream that converts
  # (IO_CBUF_CAPA_MIN), or the first push back where that is larger.
  # A push back that does not fit is an error.
  RBUF_CAPA = 8192
  CBUF_CAPA = 131_072
  private_constant :RBUF_CAPA, :CBUF_CAPA

  def buffer_capa
    Primitive.attr! :hidden
    decoding? ? CBUF_CAPA : RBUF_CAPA
  end

  # More bytes into the buffer; none marks the end.
  def fill
    Primitive.attr! :hidden
    @capa ||= buffer_capa
    park_to_read unless IO.send(:scheduler_taking, :io_read)
    return if decoding? && decoded_rest

    chunk = read_memory(8192)
    chunk = decoded(chunk) if decoding? && !chunk.is_a?(Integer)
    if chunk.nil?
      @eof = true
    elsif chunk.is_a?(Integer)
      # A descriptor that cannot wait says "nothing yet" rather than
      # waiting, so the read tries again.
      # A directory gives EISDIR only on the read. Ruby reports it
      # from the outer call, not from the buffer filler.
      site = -chunk == Errno::EISDIR::Errno ? +"io_fread" : +"io_fillbuf"
      raise SystemCallError.new(label, -chunk, site) unless -chunk == Errno::EAGAIN::Errno

      wait_again(READABLE)
    else
      # The bytes join the buffer as they are: the buffer's own
      # encoding decides what was read, not the chunk's.
      # A stream that gives no encoding reads in the default one, as it
      # is when the bytes arrive.
      @buffer.force_encoding(Encoding.default_external) if @buffer.empty? && @external.nil? && !@binmode
      chunk.force_encoding(@buffer.encoding)
      @buffer << chunk
    end
  end

  # An empty read buffer in the stream's encoding: binary in binary mode.
  # The access that a mode needs must be one that the descriptor has, as
  # rb_io_initialize checks it with fcntl.
  # Bytes that a read took from the descriptor and did not give out.
  # A stream that contains them is ready to read, whatever the
  # descriptor itself says.
  def buffered?
    Primitive.attr! :hidden
    !@buffer.empty?
  end

  def check_access
    Primitive.attr! :hidden
    # A duplex handle writes to its twin, so this descriptor only has
    # to allow reads.
    return if @twin

    flags = Primitive.zr_io_flags(@fd)
    raise SystemCallError.new(nil, -flags) if flags < 0

    access = flags & ACCESS.fetch(:mask)
    return if access == ACCESS.fetch(:both)

    want = @readable && @writable ? :both : (@writable ? :write : :read)
    raise Errno::EINVAL unless access == ACCESS.fetch(want)
  end

  # An internal encoding converts the bytes as they are read. A stream
  # with both ends given requests this.
  def transcoded(text)
    Primitive.attr! :hidden
    return text if text.nil? || @internal.nil? || decoding?

    text.encode(@internal, @external || Encoding.default_external, **@read_options)
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    stopped_conversion(text)
  end

  # rb_econv_convert stops at a byte it cannot convert: the text that
  # this read made is dropped, the bytes after the error stay for the
  # next read, and the read raises the converter's error.
  def stopped_conversion(text)
    Primitive.attr! :hidden
    from = @external || Encoding.default_external
    converter = Encoding::Converter.new(from, @internal, **@read_options)
    rest = text.dup.force_encoding(from)
    converter.primitive_convert(rest, +"")
    push_back(rest) unless rest.empty?
    raise converter.last_error
  end

  def clear_buffer
    Primitive.attr! :hidden
    @buffer = fresh_buffer
    @cooked = 0
    @char_front = 0
  end

  # What is read arrives in the stream's own encoding: binary where the
  # stream is binary, else the external encoding it was opened with.
  def fresh_buffer
    Primitive.attr! :hidden
    (+"").force_encoding(read_encoding)
  end

  # io_read_encoding: the encoding that the stream's bytes are in.
  def read_encoding
    Primitive.attr! :hidden
    return @internal if decoding?

    @external || (@binmode ? Encoding::BINARY : Encoding.default_external)
  end

  # A stream that converts from a stateful encoding, such as ISO-2022-JP,
  # or from one that is not ASCII compatible, such as UTF-16: its bytes
  # cannot be read one at a time, so the fill converts as it reads, as
  # CRuby's character buffer does. The buffer holds the internal
  # encoding, and the newline decorator reads that.
  def decoding?
    Primitive.attr! :hidden
    return false if @internal.nil?

    external = @external || Encoding.default_external
    stateful?(external) || !external.ascii_compatible?
  end

  # One raw chunk converted with the stream's read converter, whose state
  # goes on to the next chunk; at the end, nil after what the
  # converter's finish gives.
  def decoded(chunk)
    Primitive.attr! :hidden
    # The universal newline decorator works inside the converter, where
    # the text is ASCII-compatible, not on the wide text it gives.
    options = @universal ? @read_options.merge(universal_newline: true) : @read_options
    @read_converter ||= Encoding::Converter.new(@external || Encoding.default_external, @internal, **options)
    if chunk.nil?
      tail = @read_converter.finish
      @buffer << tail.force_encoding(@buffer.encoding) unless tail.empty?
      return nil
    end
    out = +""
    result = @read_converter.primitive_convert(chunk, out, nil, nil, partial_input: true)
    # The text before a byte the converter cannot take reads first. The
    # error waits for the read that needs more, and the bytes after it
    # convert at the fill after that.
    unless result == :source_buffer_empty
      @read_error = @read_converter.last_error
      @read_rest = chunk
    end
    out
  end

  # The fill of a converting stream that has met a byte it cannot take:
  # the error, which drops what the read made so far, as
  # rb_econv_convert's caller does; then the bytes after it. True when it
  # did either, so the fill reads nothing new.
  def decoded_rest
    Primitive.attr! :hidden
    if (error = @read_error)
      @read_error = nil
      clear_buffer
      raise error
    end
    rest = @read_rest or return false
    @read_rest = nil
    @buffer << decoded(rest).force_encoding(@buffer.encoding)
    true
  end

  # The universal newline decorator over the bytes read so far: CRLF and
  # a lone CR become LF. A CR at the end waits for the next byte, unless
  # the stream has ended. Only reads of characters and lines, and a read
  # of the whole stream, see the decorated bytes; read(length) does not.
  # A character read cooks at most `budget` bytes, as CRuby's converter
  # stops after its first output, so a later binmode reads the rest raw.
  def cook(budget = nil)
    Primitive.attr! :hidden
    return unless @universal && @cooked < @buffer.bytesize && !decoding?

    # A character read cooks only when nothing at the head is cooked: a
    # character's bytes past a cooked head hold no CR.
    return if budget && @cooked.positive?

    left = @buffer.bytesize - @cooked
    size = budget ? [budget, left].min : left

    # A CR at the end of the budget takes the byte after it along.
    size += 1 if size < left && @buffer.getbyte(@cooked + size - 1) == 13
    raw = @buffer.byteslice(@cooked, size).b
    held = size == left && !@eof && raw.end_with?("\r") ? 1 : 0
    done = raw.byteslice(0, raw.bytesize - held).gsub(/\r\n?/n, "\n")
    rest = @buffer.byteslice(@cooked + size - held, left - size + held).b
    @buffer = (@buffer.byteslice(0, @cooked).b << done << rest).force_encoding(@buffer.encoding)
    @cooked += done.bytesize
  end

  # A fill that the universal decorator reads.
  def fill_cooked(budget = nil)
    Primitive.attr! :hidden
    fill
    cook(budget)
  end

  # One character off the buffer, as io_getc takes it: a whole character
  # in the read encoding, or one byte where no character starts. Where
  # the buffer ends inside a character, the next bytes join it one at a
  # time until it is whole or broken, or the stream ends.
  def read_char
    Primitive.attr! :hidden
    enc = read_encoding
    onig = Regexp.encoder(enc)
    cook(char_budget(onig))
    if @buffer.empty? && !@eof
      fill
      cook(char_budget(onig))
    end
    # A CR that the universal decorator holds waits for the next byte.
    while @universal && !@eof && @cooked.zero? && !@buffer.empty?
      fill
      cook(char_budget(onig))
    end
    return nil if @buffer.empty?

    n = onig.precise_mbclen(@buffer, 0)
    if n < -1
      n = @buffer.bytesize
      loop do
        fill_cooked while !@eof && @buffer.bytesize <= n
        break if @buffer.bytesize <= n

        n += 1
        break unless onig.precise_mbclen(@buffer.byteslice(0, n), 0) < -1
      end
      # A converting stream's character buffer ends inside a character:
      # its bytes come one unit at a time (rb_enc_mbclen).
      n = [onig.min_len, n].min if (@universal || @internal) && onig.precise_mbclen(@buffer.byteslice(0, n), 0) < -1
    elsif n < 0
      n = @internal && !decoding? ? unreadable_length(enc) : 1
    end
    take(n).force_encoding(enc)
  end

  # The bytes that a character read cooks: the first character's, as
  # CRuby's converter stops after its first output; all a character may
  # take where the head is no whole character yet.
  def char_budget(onig)
    Primitive.attr! :hidden
    n = @buffer.empty? ? -1 : onig.precise_mbclen(@buffer, 0)
    n.positive? ? n : onig.max_len
  end

  # A converting stream reads an invalid character as its converter does:
  # the error bytes are one character, and what follows is read again.
  def unreadable_length(enc)
    Primitive.attr! :hidden
    converter = Encoding::Converter.new(enc, @internal)
    converter.primitive_convert(@buffer.dup.force_encoding(enc), +"")
    error = converter.primitive_errinfo[3]
    error ? [error.bytesize, 1].max : 1
  end

  # Bytes in front of the buffer, for ungetc and ungetbyte to hand back.
  def push_back(text)
    Primitive.attr! :hidden
    @capa ||= [text.bytesize, buffer_capa].max
    raise IOError, decoding? ? +"ungetc failed" : +"ungetbyte failed" if @capa < text.bytesize + @buffer.bytesize

    @buffer = text.b.force_encoding(@buffer.encoding) + @buffer
    @cooked += text.bytesize
    nil
  end

  # rb_io_ungetc's code point: NUM2UINT's range, where a negative Integer
  # wraps.
  def ungot_code(code)
    Primitive.attr! :hidden
    raise RangeError, "integer #{code} too big to convert to 'unsigned int'" if code > 0xFFFF_FFFF
    raise RangeError, "integer #{code} too small to convert to 'unsigned int'" if code < -0x8000_0000

    code.negative? ? code & 0xFFFF_FFFF : code
  end

  # check_getline_args: a separator in another encoding than the
  # stream's is an error, except ruby's own default, which is written in
  # the stream's encoding. A stream that converts reads in its internal
  # encoding, which io_read_encoding gives then.
  def stream_separator(separator)
    Primitive.attr! :hidden
    enc = @internal || read_encoding
    return separator if separator.nil? || separator.encoding == enc
    return separator if separator.ascii_only? && (separator.empty? || enc.ascii_compatible?)
    # rb_str_buf_cat_ascii writes the dummy UTF-16 and UTF-32 big-endian,
    # with no byte order mark.
    if separator.equal?(String.default_rs)
      unit = { Encoding::UTF_16 => Encoding::UTF_16BE, Encoding::UTF_32 => Encoding::UTF_32BE }.fetch(enc, enc)
      return "\n".encode(unit).force_encoding(enc)
    end

    raise ArgumentError, "encoding mismatch: #{enc} IO with #{separator.encoding} RS"
  end

  # Whether `at` starts a character. A separator counts only there. In
  # UTF-8 and the single-byte encodings, every ASCII byte does.
  def char_boundary?(at)
    Primitive.attr! :hidden
    return true if at.zero?
    # In UTF-8 only a continuation byte (0x80..0xBF) is inside a character.
    if read_encoding.equal?(Encoding::UTF_8)
      b = @buffer.getbyte(at)
      return !(b && b >= 0x80 && b <= 0xBF)
    end

    onig = Regexp.encoder(read_encoding)
    onig.max_len == 1 || onig.left_adjust_char_head(@buffer, 0, at, @buffer.bytesize) == at
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
    # A negative limit is no limit.
    unless limit.nil?
      limit = implicit_integer(limit)
      raise RangeError, +"bignum too big to convert into 'long'" unless limit.bit_length < 64
    end
    [separator, limit&.negative? ? nil : limit]
  end

  # rb_io_getline_0 with a limit, step by step. appendline reads to the
  # separator's last byte or to the limit; a line ends where the whole
  # separator ends on a character's start. A limit that runs out on that
  # last byte with no whole separator leaves 0, which appendline takes as
  # no limit, so the line reads on to the next separator: ruby's own
  # quirk. A limit inside a character reads on, a byte at a time, to its
  # end, at most 16 bytes. In an encoding whose characters are wider than
  # a byte, search_delim finds the separator's last character, whole and
  # at a character's start, not its last byte.
  def limited_line(separator, limit, paragraph)
    Primitive.attr! :hidden
    newline = separator.getbyte(separator.bytesize - 1)
    size = separator.bytesize
    wide = Regexp.encoder(read_encoding).min_len > 1
    last = separator[-1].b if wide
    pos = 0
    left = limit
    extra = 16
    while true
      byte = nil
      while true
        fill_cooked if pos >= @buffer.bytesize && !@eof
        break if pos >= @buffer.bytesize

        byte = @buffer.getbyte(pos)
        pos += 1
        left -= 1
        break if (wide ? ends_with?(last, pos) : byte == newline) || left == 0

        byte = nil
      end
      return(pos.zero? ? nil : take(pos)) if byte.nil? && pos >= @buffer.bytesize && @eof

      if wide ? ends_with?(last, pos) : byte == newline
        next if pos < size || !char_boundary?(pos - size)

        if @buffer.byteslice(pos - size, size) == separator
          line = take(pos)
          skip_newlines if paragraph
          return line
        end
      end
      next unless left.zero?

      if extra.positive? && whole_char(pos) > pos
        left = 1
        extra -= 1
        next
      end
      @cut = true
      return take(pos)
    end
  end

  # Whether the buffer's first `pos` bytes end with the character `last`,
  # which starts on a character's start.
  def ends_with?(last, pos)
    Primitive.attr! :hidden
    pos >= last.bytesize && char_boundary?(pos - last.bytesize) && @buffer.byteslice(pos - last.bytesize, last.bytesize).b == last
  end

  # Paragraph mode's newlines before a paragraph, read as they arrive: a
  # fresh stream's buffer is empty until it is filled.
  def skip_newlines
    Primitive.attr! :hidden
    while true
      fill_cooked if @buffer.empty? && !@eof
      break unless @buffer.start_with?("\n")

      take(1)
    end
  end

  # A line the limit cut short counts no line: `@cut` says so, as
  # rb_io_getline_0 leaves fptr->lineno alone then.
  def read_line(separator, limit)
    Primitive.attr! :hidden
    @cut = false
    cook
    limit = external_limit(limit) if limit && @internal && !decoding?
    if separator.nil?
      fill_cooked until @eof
      return nil if @buffer.empty?
      return take(@buffer.bytesize) unless limit

      n = whole_char(limit)
      @cut = n >= limit
      return take(n)
    end
    paragraph = separator.empty?
    separator = paragraph ? +"\n\n" : buffered_separator(separator)
    skip_newlines if paragraph
    return limited_line(separator, limit, paragraph) if limit
    from = 0
    while true
      # A byte offset: `take` counts bytes, and a character index would
      # also walk the whole buffer for every line.
      at = Primitive.zr_str_find_from(@buffer, separator, from)
      if at && !char_boundary?(at)
        from = at + 1
        next
      end
      if at
        stop = at + separator.bytesize
        if limit && limit < stop
          stop = whole_char(limit)
          @cut = stop < at + separator.bytesize
        end
        line = take(stop)
        skip_newlines if paragraph
        return line
      end
      if limit && @buffer.bytesize >= limit
        @cut = true
        return take(whole_char(limit))
      end
      break if @eof

      from = [@buffer.bytesize - separator.bytesize + 1, 0].max
      fill_cooked
    end
    return nil if @buffer.empty?

    take(@buffer.bytesize)
  end

  # rb_io_getline: a stream that converts what it reads counts the limit
  # in bytes of the internal encoding. Its buffer holds the external
  # bytes, so the limit becomes the external bytes of the characters
  # whose conversion reaches it.
  def external_limit(limit)
    Primitive.attr! :hidden
    from = @external || Encoding.default_external
    at = 0
    size = 0
    while size < limit
      fill_cooked while !@eof && @buffer.bytesize < at + 16
      break if at >= @buffer.bytesize

      char = @buffer.byteslice(at, 16).force_encoding(from)[0]
      size += begin
        char.encode(@internal, from, **@read_options).bytesize
      rescue EncodingError
        char.bytesize
      end
      at += char.bytesize
    end
    at
  end

  # The separator as the buffer holds it. The buffer has the bytes before
  # the read conversion, so a separator in the internal encoding is
  # encoded back to the external one. A dummy encoding's separator keeps
  # its byte order mark, which no line of the stream has, as in ruby.
  def buffered_separator(separator)
    Primitive.attr! :hidden
    return separator if @internal.nil? || decoding? || @internal.dummy? || separator.encoding != @internal

    separator.encode(@external || Encoding.default_external)
  rescue EncodingError
    separator
  end

  # A limit that ends inside a character reads on, one byte at a time
  # and at most 16 bytes more, until the character is whole, as
  # rb_io_getline_0 relaxes it. A single-byte encoding counts bytes.
  def whole_char(n)
    Primitive.attr! :hidden
    fill_cooked while !@eof && @buffer.bytesize < n
    n = [n, @buffer.bytesize].min
    onig = Regexp.encoder(read_encoding)
    return n if onig.max_len == 1

    16.times do
      break if n.zero?

      head = onig.left_adjust_char_head(@buffer, 0, n - 1, n)
      break unless onig.precise_mbclen(@buffer.byteslice(head, n - head), 0) < -1

      fill_cooked while !@eof && @buffer.bytesize <= n
      break if @buffer.bytesize <= n

      n += 1
    end
    n
  end

  # The first `n` bytes out of the buffer, which keeps the rest.
  def take(n)
    Primitive.attr! :hidden
    taken = Primitive.zr_str_shift_front(@buffer, n)
    cooked = @cooked - taken.bytesize
    @cooked = cooked.negative? ? 0 : cooked
    @char_front = [@char_front - taken.bytesize, 0].max if @char_front.positive?
    taken
  end

  # The bytes in the buffer: at most `length` bytes, unless it is negative.
  def buffered_bytes(length)
    Primitive.attr! :hidden
    take(length.negative? ? @buffer.bytesize : [length, @buffer.bytesize].min).force_encoding(Encoding::BINARY)
  end

  # One read(2) past the buffer, or a pread(2) at `offset`; nil at the end.
  def copy_read(size, offset)
    Primitive.attr! :hidden
    # nogvl_copy_stream_read_write waits on a descriptor that is not
    # ready, also on one that is non-blocking.
    loop do
      park_until(READABLE)
      chunk = offset.negative? ? Primitive.zr_io_read(@fd, size) : Primitive.zr_io_pread(@fd, size, offset)
      # The bytes copied are binary, as the destination's `write` sees them.
      return chunk && Primitive.zr_str_set_binary(chunk) unless chunk.is_a?(Integer)
      raise SystemCallError.new(offset.negative? ? +"read" : +"pread", -chunk) unless -chunk == Errno::EAGAIN::Errno

      wait_again(READABLE)
    end
  end

  # The line without its separator, as rb_io_getline_0 cuts it: a "\n"
  # takes one "\r" before it too, a paragraph loses its "\n\n", and a
  # line that the limit or the end stopped keeps all its bytes.
  def chomp_line(line, separator)
    Primitive.attr! :hidden
    return line if separator.nil?

    separator = +"\n\n" if separator.empty?
    bytes = line.b
    return line unless bytes.end_with?(separator.b)

    # A separator that would start inside a character was not matched.
    start = bytes.bytesize - separator.bytesize
    if start.positive? && line.encoding.equal?(Encoding::UTF_8)
      b = bytes.getbyte(start)
      return line if b >= 0x80 && b <= 0xBF
    end
    cut = separator.bytesize
    cut += 1 if separator.b == "\n" && bytes.getbyte(-2) == 0x0D && bytes.bytesize > 1
    line.byteslice(0, line.bytesize - cut)
  end
end

STDIN = IO.new(0, +"r", name: +"<STDIN>")
STDOUT = IO.new(1, +"w", name: +"<STDOUT>")
STDERR = IO.new(2, +"w", name: +"<STDERR>")
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
  # rb_f_puts: a call of $stdout's own puts, which a program may
  # define; when $stdout is the receiver, its write takes the lines.
  def puts(*objects)
    out = $stdout
    return out.__send__(:puts, *objects) unless out.equal?(self)

    IO.send(:each_line_of, objects) { |*parts| IO.send(:writev, out, parts) }
    nil
  end

  # `$,` goes between the objects and `$\` after the last one. This is
  # the difference between `print` and `puts`. Only `write` is called on
  # `$stdout`, so an object in its place needs only that one method.
  # CRuby needs no more than that.
  def print(*objects) = IO.print_to($stdout, objects)

  # Alone among the writers, `p` flushes: CRuby's rb_f_p ends with
  # `rb_io_flush` when `$stdout` is an IO, so what `p` wrote survives
  # an `exit!` while what `puts` or `print` wrote does not.
  # rb_f_p: the writes and the flush are uninterruptible, so `p` is no
  # blocking point for handle_interrupt.
  def p(*objects)
    if Primitive.zr_threaded
      # Only the writes are held back; each inspect runs before them.
      shown = objects.map { |object| Primitive.zr_inspect(object) }
      Thread.send(:uninterruptible) { IO.send(:p_to, $stdout, shown, false) }
    else
      IO.send(:p_to, $stdout, objects, true)
    end
    Primitive.zr_ary_len_m(objects) <= 1 ? Primitive.zr_ary_at_m(objects, 0) : objects
  end

  # rb_f_printf: to $stdout when the first argument is a String, else to
  # the first argument, whatever it is, with its `write`.
  def printf(*args)
    return nil if args.empty?

    out = String === args.first ? $stdout : args.shift
    out.write(Kernel.format(*args))
    nil
  end

  # A bare read reads ARGF: the files ARGV names, and standard input
  # where it names none.
  # rb_f_gets: a call of ARGF's own gets, which a program may redefine.
  def gets(*args, **options) = ARGF.__send__(:gets, *args, **options)

  def readline(*args, **options) = ARGF.readline(*args, **options)

  def readlines(*args, **options) = ARGF.readlines(*args, **options)

  # rb_f_open: an object that responds to `to_open` opens itself, and
  # the block's stream closes after the block. Any other object is a
  # file name, a leading `|` included.
  # rb_f_open: an object without to_open is a path, converted as one.
  def open(path, *rest, **options, &block)
    return File.open(File.send(:path_of, path), *rest, **options, &block) unless path.respond_to?(:to_open)

    io = path.to_open(*rest, **options)
    return io unless block

    begin
      yield io
    ensure
      io.close if io.respond_to?(:close)
    end
  end

  private :puts, :print, :p, :printf, :gets, :readline, :readlines, :open
  module_function :puts, :print, :p, :printf, :gets, :readline, :readlines, :open
end

# The errors that libSystem returns, each a class under Errno with the
# errno that it represents.
class SystemCallError
  # The errno hides from reflection, as ruby's does.
  def errno = Primitive.zr_hidden_get(self, :__errno__)

  # SystemCallError itself takes an errno, and becomes the Errno class
  # that represents it; an Errno class has its own. `func` is the name of
  # the call that failed, and shows only next to a message.
  def initialize(*args)
    if self.class.equal?(SystemCallError)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless args.size.between?(1, 3)

      message, errno, func = args
      message, errno = nil, message if args.size == 1 && Primitive.zr_fixnum_p_m(message)
      klass = Errno.for(Primitive.zr_index_operand_m(errno)) unless errno.nil?
      Primitive.zr_exc_set_class(self, klass) if klass
    else
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

      message, func = args
      errno = self.class.const_get(:Errno)
    end
    text = errno.nil? ? +"unknown error" : Errno.text(Primitive.zr_index_operand_m(errno))
    unless message.nil?
      message = Primitive.zr_str_operand(message)
      text << " @ #{func}" unless func.nil?
      text << " - #{message}"
    end
    super(text)
    Primitive.zr_hidden_set(self, :__errno__, errno)
    self
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

# One class for each row of lib/zr/runtime/core/errno.rb, and its other names.
module Errno
  CODES.each do |name, code|
    klass = Class.new(SystemCallError)
    klass.const_set(:Errno, code)
    const_set(name, klass)
  end
  ALIASES.each { |name, to| const_set(name, const_get(to)) }

  def self.for(code)
    Primitive.attr! :hidden
    CODES.key(code)&.then { |name| const_get(name) }
  end

  def self.text(code)
    Primitive.attr! :hidden
    message = Primitive.zr_io_strerror(code)
    message.start_with?("Unknown error") ? "Unknown error: #{code}" : message
  end
end

# How a non-blocking call reports "would block": the error class that
# the caller rescues includes the direction as a module.
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

# Waiting on one descriptor, over poll(2). Named events return the
# stream itself; a plain events mask returns the events that became ready.
class IO
  EVENT_NAMES = { read: POLL_IN, readable: POLL_IN, r: POLL_IN,
                  write: POLL_OUT, writable: POLL_OUT, w: POLL_OUT,
                  priority: POLL_PRI, rw: POLL_IN | POLL_OUT, read_write: POLL_IN | POLL_OUT,
                  readable_writable: POLL_IN | POLL_OUT }.freeze
  private_constant :EVENT_NAMES

  # io_wait: two arguments that are not Symbols are an event mask and a
  # timeout, and the result is the events that came ready. Any other form
  # takes event names and at most one timeout, and returns the stream.
  def wait(*args)
    if args.size == 2 && args.none?(Symbol)
      events = Integer.send(:int_operand, args[0])
      raise ArgumentError, +"Events must be positive integer!" unless events.positive?

      ready = poll_once(events, args[1])
      return ready.zero? ? nil : ready
    end
    events = 0
    timeout = given = nil
    args.each do |arg|
      if arg.is_a?(Symbol)
        events |= EVENT_NAMES.fetch(arg) { raise ArgumentError, "unsupported mode: #{arg}" }
      elsif given
        raise ArgumentError, +"timeout given more than once"
      else
        IO.send(:time_interval, arg)
        timeout = arg
        given = true
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
    Primitive.attr! :hidden
    timeout = IO.send(:time_interval, timeout)
    if (scheduler = Fiber.current_scheduler)
      ready = scheduler.io_wait(self, events, timeout)
      return ready.is_a?(Integer) ? ready & events : 0
    end
    # rb_timeout_to_hrtime: a wait takes no infinite timeout, where select does.
    raise RangeError, +"Inf out of Time range" if timeout == Float::INFINITY

    deadline = timeout && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (timeout * 1e9).round
    ready = Thread.current.send(:wait_io, fileno, events, deadline, gives_way: true)
    raise SystemCallError.new(label, -ready, +"io_wait") if ready.negative?

    ready & events
  end
end
