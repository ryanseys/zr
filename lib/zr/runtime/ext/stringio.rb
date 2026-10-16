# frozen_string_literal: true

# stringio.c, in ruby: an IO over a String. The buffer is the same String
# that the program gave, so a write shows through it, and a change to it
# shows here. A Strio contains what the extension keeps in `struct
# StringIO`: the string, the encoding, the position, the line number and
# the mode. A copy of a stream shares its Strio, as a copy in C shares the
# struct. Whether this object can still read or write is its own state.
class StringIO
  include Enumerable

  # T_DATA, of a type that is not frozen-shareable.
  Ractor.send(:data_class!, self)

  VERSION = "3.2.1.dev"
  MAX_LENGTH = 0x7fff_ffff_ffff_ffff

  # struct StringIO.
  class Strio
    Primitive.attr! :hidden

    attr_accessor :string, :enc, :pos, :lineno, :flags

    def initialize
      @string = nil
      @enc = nil
      @pos = 0
      @lineno = 0
      @flags = 0
    end

    # get_enc: the encoding set, else the string's.
    def encoding = @enc || @string&.encoding
  end
  private_constant :Strio

  # The FMODE bits a mode sets.
  READABLE = 0x1
  WRITABLE = 0x2
  READWRITE = 0x3
  BINMODE = 0x4
  APPEND = 0x40
  TRUNC = 0x800
  SETENC_BY_BOM = 0x100000
  private_constant :READABLE, :WRITABLE, :READWRITE, :BINMODE, :APPEND, :TRUNC, :SETENC_BY_BOM

  def self.new(*args, **opts, &block)
    if block
      name = Primitive.zr_obj_as_string(self)
      warn("#{name}::new() does not take block; use #{name}::open() instead", uplevel: 0)
    end
    super
  end

  def self.open(*args, **opts)
    io = new(*args, **opts)
    return io unless block_given?

    begin
      yield io
    ensure
      io.send(:finalize)
    end
  end

  def initialize(*args, **opts)
    ptr = Primitive.zr_hidden_get(self, :__strio__) || Primitive.zr_state_set(self, :__strio__, Strio.new)
    init(args, opts, ptr)
  end

  def initialize_copy(orig)
    orig = StringIO.send(:convert, orig)
    return self if equal?(orig)

    ptr = orig.send(:strio)
    Primitive.zr_state_set(self, :__strio__, ptr)
    Primitive.zr_state_set(self, :__open__, Primitive.zr_hidden_get(orig, :__open__))
    self
  end

  def reopen(*args, **opts)
    Primitive.zr_frozen_error(self) if frozen?
    return initialize_copy(args[0]) if args.size == 1 && opts.empty? && !args[0].is_a?(String)

    init(args, opts, changing_strio)
  end

  def string = strio.string

  def string=(string)
    ptr = changing_strio
    ptr.flags &= ~READWRITE
    string = Primitive.zr_str_operand(string)
    ptr.flags = string.frozen? ? READABLE : READWRITE
    ptr.pos = 0
    ptr.lineno = 0
    ptr.string = string
  end

  def lineno = strio.lineno

  def lineno=(lineno)
    changing_strio.lineno = Primitive.zr_index_operand_m(lineno)
  end

  def binmode
    ptr = changing_strio
    ptr.enc = Encoding::BINARY
    ptr.string.force_encoding(Encoding::BINARY) if writable?
    self
  end

  def close
    changing_strio
    Primitive.zr_state_set(self, :__open__, 0)
    nil
  end

  def close_read
    ptr = changing_strio
    raise IOError, "closing non-duplex IO for reading" unless ptr.flags.anybits?(READABLE)

    Primitive.zr_state_set(self, :__open__, Primitive.zr_hidden_get(self, :__open__) & ~READABLE)
    nil
  end

  def close_write
    ptr = changing_strio
    raise IOError, "closing non-duplex IO for writing" unless ptr.flags.anybits?(WRITABLE)

    Primitive.zr_state_set(self, :__open__, Primitive.zr_hidden_get(self, :__open__) & ~WRITABLE)
    nil
  end

  def closed?
    strio
    !open?(READWRITE)
  end

  def closed_read?
    strio
    !open?(READABLE)
  end

  def closed_write?
    strio
    !open?(WRITABLE)
  end

  def eof = end_of?(readable)

  def eof? = end_of?(readable)

  def fcntl(*)
    strio
    raise NotImplementedError, "fcntl() function is unimplemented on this machine"
  end

  def flush
    strio
    self
  end

  def fsync
    strio
    0
  end

  def pos = strio.pos

  def pos=(pos)
    ptr = changing_strio
    at = Primitive.zr_index_operand_m(pos)
    raise Errno::EINVAL if at.negative?

    ptr.pos = at
  end

  def rewind
    ptr = changing_strio
    ptr.pos = 0
    ptr.lineno = 0
    0
  end

  def seek(amount, whence = nil)
    ptr = changing_strio
    amount = Primitive.zr_index_operand_m(amount)
    raise IOError, "closed stream" unless open?(READWRITE)

    offset = case whence.nil? ? 0 : Primitive.zr_index_operand_m(whence)
             when 0 then 0
             when 1 then ptr.pos
             when 2 then ptr.string.nil? ? 0 : ptr.string.bytesize
             else raise Errno::EINVAL, "invalid whence"
             end
    raise Errno::EINVAL if amount > MAX_LENGTH - offset || (amount + offset).negative?

    ptr.pos = amount + offset
    0
  end

  def sync
    strio
    true
  end

  def sync=(value)
    strio
    value
  end

  def tell = strio.pos

  def each(*args, **opts, &block)
    ptr = readable
    return enum_for(__method__, *args, **opts) unless block

    rs, limit, chomp = line_args(ptr, args, opts)
    raise ArgumentError, "invalid limit: 0 for each_line" if limit.zero?

    while (line = getline(ptr, rs, limit, chomp))
      yield line
    end
    self
  end
  alias each_line each

  def each_byte
    return enum_for(:each_byte) unless block_given?

    while (ptr = to_read)
      byte = ptr.string.getbyte(ptr.pos)
      ptr.pos += 1
      yield byte
    end
    self
  end

  def each_char
    return enum_for(:each_char) unless block_given?

    while (c = getc)
      yield c
    end
    self
  end

  def each_codepoint
    return enum_for(:each_codepoint) unless block_given?

    enc = readable.encoding
    while (ptr = to_read)
      char = char_at(ptr.string, ptr.pos, ptr.string.bytesize, enc)
      ptr.pos += char.bytesize
      yield char.ord
    end
    self
  end

  def getc
    ptr = readable
    return nil if end_of?(ptr)

    char = char_at(ptr.string, ptr.pos, ptr.string.bytesize, ptr.encoding)
    ptr.pos += char.bytesize
    char
  end

  def ungetc(c)
    ptr = readable
    modifiable(ptr)
    return nil if ptr.string.nil? || c.nil?

    if c.is_a?(Integer)
      bytes = Primitive.zr_index_operand_m(c).chr(ptr.string.encoding)
    else
      c = Primitive.zr_str_operand(c)
      return nil if c.empty?

      enc = ptr.string.encoding
      c = converted(c, c.encoding, enc) if enc != c.encoding && enc != Encoding::BINARY
      bytes = c
    end
    unget_bytes(ptr, bytes)
    nil
  end

  def ungetbyte(c)
    ptr = readable
    modifiable(ptr)
    return nil if ptr.string.nil? || c.nil?

    bytes = if c.is_a?(Integer)
              (c & 0xff).chr
            else
              Primitive.zr_str_operand(c)
            end
    unget_bytes(ptr, bytes) unless bytes.empty?
    nil
  end

  def getbyte
    ptr = readable
    return nil if end_of?(ptr)

    byte = ptr.string.getbyte(ptr.pos)
    ptr.pos += 1
    byte
  end

  def gets(*args, **opts)
    ptr = readable
    rs, limit, chomp = line_args(ptr, args, opts)
    if limit.zero?
      return nil if ptr.string.nil?

      return String.new(encoding: ptr.encoding)
    end

    $_ = getline(ptr, rs, limit, chomp)
  end

  def readlines(*args, **opts)
    ptr = readable
    rs, limit, chomp = line_args(ptr, args, opts)
    raise ArgumentError, "invalid limit: 0 for readlines" if limit.zero?

    lines = []
    while (line = getline(ptr, rs, limit, chomp))
      lines << line
    end
    lines
  end

  def read(*args)
    ptr = readable
    raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

    length, buffer = args
    binary = false
    buffer = read_buffer(ptr, buffer)
    if length.nil?
      return nil if ptr.string.nil?

      len = ptr.string.bytesize
      if len <= ptr.pos
        buffer = buffer.nil? ? +"" : buffer.clear
        return buffer.force_encoding(ptr.encoding)
      end
      len -= ptr.pos
    else
      len = Primitive.zr_index_operand_m(length)
      raise ArgumentError, "negative length #{len} given" if len.negative?

      if end_of?(ptr)
        buffer&.clear
        return len.positive? ? nil : "".b
      end
      binary = true
    end

    if buffer.nil?
      buffer = substr(ptr, ptr.pos, len, binary ? Encoding::BINARY : ptr.encoding)
    else
      encoding = binary ? buffer.encoding : ptr.string.encoding
      buffer.replace(ptr.string.byteslice(ptr.pos, len))
      buffer.force_encoding(encoding)
    end
    ptr.pos += buffer.bytesize
    buffer
  end

  def pread(length, offset, buffer = nil)
    ptr = readable
    len = Primitive.zr_index_operand_m(length)
    at = Primitive.zr_index_operand_m(offset)
    raise ArgumentError, "negative string size (or size too big): #{length}" if len.negative?
    raise Errno::EINVAL, "pread: Invalid offset argument: #{offset}" if at.negative?

    buffer = read_buffer(ptr, buffer)
    return buffer.nil? ? +"" : buffer if len.zero?
    raise EOFError, "end of file reached" if outside?(ptr, at)
    return substr(ptr, at, len, Encoding::BINARY) if buffer.nil?

    buffer.replace(ptr.string.byteslice(at, len))
    buffer.force_encoding(Encoding::BINARY)
  end

  def write(*objects)
    objects.sum { |object| write_one(object) }
  end

  def putc(ch)
    ptr = writable
    modifiable(ptr)
    if ch.is_a?(String)
      return ch if ptr.string.nil?

      write_one(ch[0, 1])
    else
      c = Primitive.zr_index_operand_m(ch) & 0xff
      return ch if ptr.string.nil?

      write_one(c.chr)
    end
    ch
  end

  def isatty
    strio
    false
  end

  def tty?
    strio
    false
  end

  def pid
    strio
    nil
  end

  def fileno
    strio
    nil
  end

  def size
    string = strio.string
    string.nil? ? 0 : string.bytesize
  end

  def length
    string = strio.string
    string.nil? ? 0 : string.bytesize
  end

  def truncate(len)
    string = writable.string
    l = Primitive.zr_index_operand_m(len)
    raise Errno::EINVAL, "negative length" if l.negative?
    return 0 if string.nil?

    if l < string.bytesize
      Primitive.zr_frozen_error(string) if string.frozen?
      string.replace(string.byteslice(0, l).force_encoding(string.encoding))
    else
      StringIO.send(:cat, string, "\0" * (l - string.bytesize))
    end
    0
  end

  def external_encoding = strio.encoding

  def internal_encoding = nil

  def set_encoding(ext_enc, int_enc = nil, **opt)
    ptr = changing_strio
    enc = if ext_enc.nil?
            Encoding.default_external
          else
            begin
              Encoding.find(ext_enc.is_a?(Encoding) ? ext_enc.name : ext_enc.to_str)
            rescue ArgumentError
              IO.send(:open_options, "r:#{ext_enc}", {})[2]
            end
          end
    ptr.enc = enc
    # A chilled String keeps its encoding, as str_chilled_p spares it.
    ptr.string.force_encoding(enc) if !ptr.string.nil? && writable? && !ptr.string.frozen? && !Primitive.zr_str_chilled_m(ptr.string)
    self
  end

  def set_encoding_by_bom
    ptr = changing_strio
    return nil unless encoding_by_bom(ptr)

    ptr.enc
  end

  # IO's generic readers and writers, which StringIO shares under the
  # names ruby gives them.
  generic_readable = Primitive.zr_module_define_m(IO, :generic_readable)
  generic_readable.module_eval do
    def readchar
      c = getc
      raise EOFError, "end of file reached" if c.nil?

      c
    end

    def readbyte
      c = getbyte
      raise EOFError, "end of file reached" if c.nil?

      c
    end

    def readline(*args, **opts)
      line = gets(*args, **opts)
      raise EOFError, "end of file reached" if line.nil?

      line
    end

    def sysread(*args)
      val = read(*args)
      raise EOFError, "end of file reached" if val.nil?

      val
    end

    def readpartial(*args)
      val = read(*args)
      raise EOFError, "end of file reached" if val.nil?

      val
    end

    # strio_read_nonblock takes one or two arguments, and any keywords.
    def read_nonblock(length, buffer = (no_buffer = true; nil), **opts)
      val = no_buffer ? read(length) : read(length, buffer)
      return nil if val.nil? && opts[:exception] == false
      raise EOFError, "end of file reached" if val.nil?

      val
    end
  end

  generic_writable = Primitive.zr_module_define_m(IO, :generic_writable)
  generic_writable.module_eval do
    def <<(obj)
      write(obj)
      self
    end

    def print(*objects) = IO.send(:print_to, self, objects)

    def printf(*args)
      write(format(*args))
      nil
    end

    def puts(*objects)
      IO.send(:each_line_of, objects) { |*parts| write(*parts) }
      nil
    end

    def syswrite(str) = write(str)

    def write_nonblock(str, **) = write(str)
  end

  include generic_readable
  include generic_writable

  class << self
    private

    # rb_convert_type to StringIO through `to_strio`.
    def convert(obj)
      Primitive.attr! :hidden
      return obj if obj.is_a?(StringIO)

      converted = obj.respond_to?(:to_strio, true) ? obj.to_strio : nil
      raise TypeError, "no implicit conversion of #{Primitive.zr_class_name_of(obj)} into StringIO" if converted.nil?
      raise TypeError, cant_convert_gives(obj, "StringIO", :to_strio, converted) unless converted.is_a?(StringIO)

      converted
    end

    # rb_str_cat: bytes onto a String that keeps its encoding.
    def cat(str, bytes)
      Primitive.attr! :hidden
      encoding = str.encoding
      str.force_encoding(Encoding::BINARY) << bytes.b
      str.force_encoding(encoding)
    end
  end

  private

  # get_strio_for_read: the struct, once initialize made one. A frozen
  # StringIO still reads.
  def strio
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__strio__) or raise IOError, "uninitialized stream"
  end

  # get_strio: the struct of a stream that this call changes, which a
  # frozen StringIO refuses.
  def changing_strio
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if frozen?
    strio
  end

  # strio_readbuf: the buffer that a read fills, as a String that can
  # change and is not the stream's own.
  def read_buffer(ptr, buffer)
    Primitive.attr! :hidden
    return nil if buffer.nil?

    buffer = Primitive.zr_str_operand(buffer)
    Primitive.zr_frozen_error(buffer) if buffer.frozen?
    raise ArgumentError, "cannot read into the underlying string" if buffer.equal?(ptr.string)

    buffer
  end

  # STRIO_MODE_SET_P: this object and its struct both allow `mode`.
  def open?(mode)
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__open__).to_i.anybits?(mode) && strio.flags.anybits?(mode)
  end

  def readable
    Primitive.attr! :hidden
    ptr = strio
    raise IOError, "not opened for reading" unless open?(READABLE)

    ptr
  end

  def writable
    Primitive.attr! :hidden
    ptr = changing_strio
    raise IOError, "not opened for writing" unless open?(WRITABLE)

    ptr
  end

  def writable?
    Primitive.attr! :hidden
    open?(WRITABLE)
  end

  def outside?(ptr, pos)
    Primitive.attr! :hidden
    ptr.string.nil? || pos >= ptr.string.bytesize
  end

  def end_of?(ptr)
    Primitive.attr! :hidden
    outside?(ptr, ptr.pos)
  end

  def to_read
    Primitive.attr! :hidden
    ptr = readable
    end_of?(ptr) ? nil : ptr
  end

  def modifiable(ptr)
    Primitive.attr! :hidden
    raise IOError, "not modifiable string" if !ptr.string.nil? && ptr.string.frozen?
  end

  # strio_init: the string and the mode, from the arguments `new` or
  # `reopen` was given.
  def init(args, opts, ptr)
    Primitive.attr! :hidden
    raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

    string, vmode = args
    vmode = opts[:mode] if vmode.nil? && opts.key?(:mode)
    flags, enc = mode_of(vmode, opts)
    if !string.nil?
      string = Primitive.zr_str_operand(string)
    elsif args.empty?
      string = String.new(encoding: Encoding.default_external)
    end

    if !string.nil? && string.frozen?
      raise Errno::EACCES if flags.anybits?(WRITABLE)
    elsif vmode.nil?
      flags |= WRITABLE
    end
    string.clear if !string.nil? && flags.anybits?(TRUNC)
    ptr.flags = flags
    ptr.string = string
    ptr.enc = args.size == 1 && !string.nil? ? string.encoding : enc
    ptr.pos = 0
    ptr.lineno = 0
    encoding_by_bom(ptr) if flags.anybits?(SETENC_BY_BOM)
    Primitive.zr_state_set(self, :__open__, Primitive.zr_hidden_get(self, :__open__).to_i | (flags & READWRITE))
    self
  end

  # rb_io_extract_modeenc: the FMODE bits and the encoding a mode and
  # the options name.
  def mode_of(vmode, opts)
    Primitive.attr! :hidden
    mode = vmode.nil? ? nil : (Integer.try_convert(vmode) || vmode)
    flags = if mode.nil?
              READABLE
            elsif mode.is_a?(Integer)
              bits = { File::RDONLY => READABLE, File::WRONLY => WRITABLE, File::RDWR => READWRITE }.fetch(mode & (File::RDONLY | File::WRONLY | File::RDWR), READABLE)
              bits |= APPEND if mode.anybits?(File::APPEND)
              bits |= TRUNC if mode.anybits?(File::TRUNC)
              bits
            else
              text = IO.send(:access_mode, Primitive.zr_str_operand(mode))
              bits = text.end_with?("+") ? READWRITE : { "r" => READABLE, "w" => WRITABLE, "a" => WRITABLE }.fetch(text)
              bits |= TRUNC if text.start_with?("w")
              bits |= APPEND if text.start_with?("a")
              bits
            end
    spec = mode.is_a?(String) ? mode : nil
    bom = spec&.split(":", 2)&.[](1)&.match?(/\Abom\|/i)
    _, binary, external, internal = IO.send(:open_options, spec, opts.except(:mode))
    flags |= SETENC_BY_BOM if bom
    flags |= BINMODE if binary || opts[:binmode]
    enc = internal || external
    enc ||= Encoding::BINARY if flags.anybits?(BINMODE)
    [flags, enc]
  end

  def encoding_by_bom(ptr)
    Primitive.attr! :hidden
    head = ptr.string.byteslice(0, 4).bytes
    name, size = if head[0, 3] == [0xef, 0xbb, 0xbf] then ["UTF-8", 3]
                 elsif head[0, 2] == [0xfe, 0xff] then ["UTF-16BE", 2]
                 elsif head == [0xff, 0xfe, 0, 0] then ["UTF-32LE", 4]
                 elsif head[0, 2] == [0xff, 0xfe] then ["UTF-16LE", 2]
                 elsif head == [0, 0, 0xfe, 0xff] then ["UTF-32BE", 4]
                 end
    ptr.enc = name && Encoding.find(name)
    return nil unless name

    ptr.pos = size
    ptr.string.force_encoding(ptr.enc) if ptr.flags.anybits?(WRITABLE)
    ptr.enc
  end

  # strio_substr: `len` bytes of the string from `pos`, in `enc`.
  def substr(ptr, pos, len, enc)
    Primitive.attr! :hidden
    rest = ptr.string.bytesize - pos
    len = rest if len > rest
    return String.new(encoding: enc) if len <= 0

    ptr.string.byteslice(pos, len).force_encoding(enc)
  end

  # rb_str_conv_enc: `str` in `to`, or `str` itself where it will not go.
  def converted(str, from, to)
    Primitive.attr! :hidden
    return str if from == to
    return str.dup.force_encoding(to) if (to.ascii_compatible? && str.ascii_only?) || to == Encoding::BINARY

    str.encode(to, from)
  rescue EncodingError
    str
  end

  # The character at byte `at` of `string` in `enc`, cut off at `stop`,
  # as rb_enc_mbclen measures it: one byte where no character starts.
  def char_at(string, at, stop, enc)
    Primitive.attr! :hidden
    string.byteslice(at, [8, stop - at].min).force_encoding(enc)[0]
  end

  # rb_enc_right_char_head: `at`, moved on to the start of the next
  # character when it falls inside one, counting from `start`.
  def right_char_head(string, start, at, stop, enc)
    Primitive.attr! :hidden
    i = start
    while i < at
      i += char_at(string, i, stop, enc).bytesize
    end
    i
  end

  def unget_bytes(ptr, bytes)
    Primitive.attr! :hidden
    string = ptr.string
    pos = ptr.pos
    len = string.bytesize
    count = bytes.bytesize
    if count > pos
      tail = pos < len ? string.byteslice(pos, len - pos) : ""
      replace_bytes(string, bytes.b + tail.b)
      ptr.pos = 0
    else
      body = pos > len ? string.b + ("\0" * (pos - len)) : string.b
      body[pos - count, count] = bytes.b
      replace_bytes(string, body)
      ptr.pos = pos - count
    end
  end

  def replace_bytes(string, bytes)
    Primitive.attr! :hidden
    encoding = string.encoding
    string.replace(bytes)
    string.force_encoding(encoding)
  end

  # prepare_getline_args: the separator, the limit and whether to chomp.
  def line_args(ptr, args, opts)
    Primitive.attr! :hidden
    raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

    unknown = opts.keys - [:chomp]
    raise ArgumentError, "unknown keyword#{'s' if unknown.size > 1}: #{unknown.map(&:inspect).join(', ')}" unless unknown.empty?

    rs, lim = args
    limit = -1
    respect_chomp = args.empty? || !rs.nil?
    case args.size
    when 0
      rs = $/
    when 1
      if !rs.nil? && !rs.is_a?(String)
        tmp = String.try_convert(rs)
        if tmp.nil?
          limit = Primitive.zr_index_operand_m(rs)
          rs = $/
        else
          rs = tmp
        end
      end
    when 2
      rs = Primitive.zr_str_operand(rs) unless rs.nil?
      limit = Primitive.zr_index_operand_m(lim) unless lim.nil?
    end
    if !ptr.string.nil? && !rs.nil?
      enc_io = ptr.encoding
      if rs.encoding != enc_io && (!rs.ascii_only? || (!rs.empty? && !enc_io.ascii_compatible?))
        raise ArgumentError, "encoding mismatch: #{enc_io.name} IO with #{rs.encoding.name} RS" unless rs.equal?($/)

        rs = "\n".encode(enc_io)
      end
    end
    [rs, limit, respect_chomp && opts[:chomp] ? true : false]
  end

  # strio_getline.
  def getline(ptr, rs, limit, chomp)
    Primitive.attr! :hidden
    string = ptr.string
    return nil if string.nil? || ptr.pos >= string.bytesize

    enc = ptr.encoding
    s = ptr.pos
    e = string.bytesize
    e = right_char_head(string, s, s + limit, e, enc) if limit.positive? && limit < e - s
    w = 0
    if rs.nil?
      w = newline_width(string, s, e) if chomp
      line = substr(ptr, ptr.pos, e - s - w, enc)
    elsif rs.empty?
      paragraph_end = nil
      p = s
      while string.getbyte(p) == 0x0a
        p += 1
        return nil if p == e
      end
      s = p
      while (p = find(string, "\n", p, e))
        p += 1
        next unless line_break_at?(string, p, e)

        paragraph_end = p - (p >= 2 && string.getbyte(p - 2) == 0x0d ? 2 : 1)
        p += string.getbyte(p) == 0x0d ? 2 : 1 while line_break_at?(string, p, e)
        e = p
        break
      end
      w = e - paragraph_end if chomp && paragraph_end
      line = substr(ptr, s, e - s - w, enc)
    elsif rs.bytesize == 1
      if (p = find(string, rs, s, e))
        e = p + 1
        w = chomp ? (p > s && string.getbyte(p - 1) == 0x0d ? 2 : 1) : 0
      end
      line = substr(ptr, ptr.pos, e - s - w, enc)
    else
      n = rs.bytesize
      if n < e - s + (chomp ? 1 : 0)
        at = find(string, rs, s, e)
        if at && at + n <= e
          e = at + n
          w = chomp ? n : 0
        end
      end
      line = substr(ptr, ptr.pos, e - s - w, enc)
    end
    ptr.pos = e
    ptr.lineno += 1
    line
  end

  # The byte index of `needle` in `string` between `from` and `stop`.
  def find(string, needle, from, stop)
    Primitive.attr! :hidden
    at = Primitive.zr_str_find_from(string, needle.b, from)
    at && at + needle.bytesize <= stop ? at : nil
  end

  def line_break_at?(string, p, e)
    Primitive.attr! :hidden
    (p < e && string.getbyte(p) == 0x0a) || (p + 1 < e && string.getbyte(p) == 0x0d && string.getbyte(p + 1) == 0x0a)
  end

  def newline_width(string, s, e)
    Primitive.attr! :hidden
    return 0 unless e > s && string.getbyte(e - 1) == 0x0a

    e - 1 > s && string.getbyte(e - 2) == 0x0d ? 2 : 1
  end

  # strio_write.
  def write_one(object)
    Primitive.attr! :hidden
    ptr = writable
    str = object.is_a?(String) ? object : Primitive.zr_obj_as_string(object)
    enc = ptr.encoding
    return 0 if enc.nil?

    enc2 = str.encoding
    if enc != enc2 && enc != Encoding::BINARY && enc != Encoding::US_ASCII
      conv = converted(str, enc2, enc)
      if conv.equal?(str) && enc2 != Encoding::BINARY && enc2 != Encoding::US_ASCII && !str.ascii_only?
        raise Encoding::CompatibilityError, "incompatible character encodings: #{enc.name} and #{enc2.name}"
      end

      str = conv
    end
    len = str.bytesize
    return 0 if len.zero?

    modifiable(ptr)
    string = ptr.string
    olen = string.bytesize
    ptr.pos = olen if ptr.flags.anybits?(APPEND)
    if ptr.pos == olen
      if enc == Encoding::BINARY || enc2 == Encoding::BINARY
        StringIO.send(:cat, string, str)
      else
        string << str
      end
    else
      # strio_extend: the end must fit in a long.
      raise ArgumentError, "string size too big" if len > MAX_LENGTH - ptr.pos

      body = string.b
      body << ("\0" * (ptr.pos - olen)) if ptr.pos > olen
      body[ptr.pos, len] = str.b
      replace_bytes(string, body)
    end
    ptr.pos += len
    len
  end

  # strio_finalize, which StringIO.open runs as its block ends.
  def finalize
    Primitive.attr! :hidden
    ptr = strio
    ptr.string = nil
    ptr.flags &= ~READWRITE
    self
  end

  # Names that strio.c defines with one C function are equal Methods.
  [[:eof, :eof?], [:isatty, :tty?], [:size, :length], [:tell, :pos]].each do |name, original|
    Primitive.zr_method_alias_of(self, name, original)
  end
end
