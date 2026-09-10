# frozen_string_literal: true

# An IO over a String. The buffer is the very String the program gave,
# so a write shows through it, and a change to it shows here.
class StringIO
  include Enumerable

  READABLE = { "r" => true, "r+" => true, "w+" => true, "a+" => true }.freeze
  WRITABLE = { "r+" => true, "w" => true, "w+" => true, "a" => true, "a+" => true }.freeze
  private_constant :READABLE, :WRITABLE

  def self.open(*args, **options)
    io = new(*args, **options)
    return io unless block_given?

    begin
      yield io
    ensure
      io.close
    end
  end

  attr_reader :string, :lineno

  def initialize(string = +"", mode = nil, **options)
    string = String.try_convert(string) || raise(TypeError, "no implicit conversion of #{string.class} into String")
    @mode = access_mode(mode || options[:mode], string)
    raise Errno::EACCES if string.frozen? && WRITABLE[@mode]

    @string = string
    @external = options[:external_encoding] ? Encoding.find(options[:external_encoding]) : string.encoding
    @string.replace("") if @mode == "w" || @mode == "w+"
    reset
  end

  def string=(other)
    @string = String.try_convert(other) || raise(TypeError, "no implicit conversion of #{other.class} into String")
    @external = @string.encoding
    reset
    other
  end

  def lineno=(value)
    @lineno = value.to_int
  end

  def pos = @pos

  alias tell pos

  def pos=(value)
    value = value.to_int
    raise Errno::EINVAL if value.negative?

    @pos = value
  end

  def rewind
    reset
    0
  end

  def seek(amount, whence = IO::SEEK_SET)
    amount = amount.to_int
    base = case whence
           when IO::SEEK_SET, nil then 0
           when IO::SEEK_CUR then @pos
           when IO::SEEK_END then @string.bytesize
           else raise Errno::EINVAL
           end
    at = base + amount
    raise Errno::EINVAL if at.negative?

    @pos = at
    0
  end

  def size = @string.bytesize

  alias length size

  def eof? = @pos >= @string.bytesize

  alias eof eof?

  def close
    @closed_read = true
    @closed_write = true
    nil
  end

  def close_read
    @closed_read = true
    nil
  end

  def close_write
    @closed_write = true
    nil
  end

  def closed? = @closed_read && @closed_write

  def closed_read? = @closed_read

  def closed_write? = @closed_write

  def fileno = nil

  def pid = nil

  def isatty = false

  alias tty? isatty

  def sync = true

  def sync=(value)
    value
  end

  def flush = self

  def fsync = 0

  def external_encoding = @external

  def internal_encoding = nil

  def set_encoding(external, _internal = nil, **_options)
    @external = external.nil? ? Encoding.default_external : Encoding.find(external)
    @string.force_encoding(@external) unless @string.frozen?
    self
  end

  def set_encoding_by_bom = nil

  def binmode = set_encoding(Encoding::BINARY)

  def inspect = "#<StringIO:0x#{format("%016x", object_id << 1)}>"

  def truncate(length)
    writable!
    length = length.to_int
    raise Errno::EINVAL, "negative length" if length.negative?

    rewrite(length, @string.bytesize - length, "") if length < @string.bytesize
    pad_to(length)
    0
  end

  # --- reading ------------------------------------------------------

  def read(length = nil, buffer = nil)
    readable!
    buffer = String.try_convert(buffer) if buffer
    text = length.nil? ? rest : @string.byteslice(@pos, length.to_int).to_s.b
    return buffer ? nil : nil if length && text.empty? && length.to_int.positive?

    @pos += text.bytesize
    buffer ? buffer.replace(text) : text
  end

  def readpartial(length, buffer = nil)
    text = read(length, buffer)
    raise EOFError, "end of file reached" if text.nil?

    text
  end

  alias sysread readpartial

  def read_nonblock(length, buffer = nil, exception: true)
    text = read(length, buffer)
    raise EOFError, "end of file reached" if text.nil? && exception

    text
  end

  def getc
    readable!
    return nil if eof?

    char = @string.byteslice(@pos..)[0]
    @pos += char.bytesize
    char
  end

  def getbyte
    readable!
    byte = @string.getbyte(@pos)
    @pos += 1 if byte
    byte
  end

  def readchar
    getc or raise EOFError, "end of file reached"
  end

  def readbyte
    getbyte or raise EOFError, "end of file reached"
  end

  def ungetc(value)
    readable!
    unget(value.is_a?(Integer) ? value.chr(@external) : value.to_s)
  end

  def ungetbyte(value)
    readable!
    unget(value.is_a?(Integer) ? (value & 0xff).chr(Encoding::BINARY) : value.to_s)
  end

  def gets(*args, chomp: false)
    readable!
    separator, limit = line_arguments(args)
    line = next_line(separator, limit)
    return $_ = nil if line.nil?

    @lineno += 1
    $_ = chomp ? chomp_line(line, separator) : line
  end

  def readline(*args, chomp: false)
    gets(*args, chomp: chomp) or raise EOFError, "end of file reached"
  end

  def each_line(*args, chomp: false, &block)
    return to_enum(:each_line, *args, chomp: chomp) unless block

    while (line = gets(*args, chomp: chomp))
      block.call(line)
    end
    self
  end

  alias each each_line

  def readlines(*args, chomp: false)
    each_line(*args, chomp: chomp).to_a
  end

  def each_char(&block)
    return to_enum(:each_char) unless block

    block.call(getc) until eof?
    self
  end

  def each_byte(&block)
    return to_enum(:each_byte) unless block

    block.call(getbyte) until eof?
    self
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) unless block

    each_char { |char| block.call(char.ord) }
  end

  def chars = each_char.to_a

  def bytes = each_byte.to_a

  def codepoints = each_codepoint.to_a

  # --- writing ------------------------------------------------------

  def write(*parts)
    writable!
    parts.sum do |part|
      text = part.is_a?(String) ? part : part.to_s
      put(text)
      text.bytesize
    end
  end

  alias syswrite write
  alias write_nonblock write

  def <<(value)
    write(value)
    self
  end

  def print(*parts)
    parts = [$_] if parts.empty?
    parts.each_with_index do |part, i|
      write($,) if i.positive? && $,
      write(part.to_s)
    end
    write($\) if $\
    nil
  end

  def printf(format, *args)
    write(format(format, *args))
    nil
  end

  def putc(value)
    write(value.is_a?(Integer) ? (value & 0xff).chr : value.to_s[0])
    value
  end

  def puts(*parts)
    return write("\n") && nil if parts.empty?

    parts.each do |part|
      list = part.is_a?(Array) ? part : Array.try_convert(part)
      next puts(*(list.empty? ? ["\n"] : list)) if list

      text = part.nil? ? "" : part.to_s
      write(text.end_with?("\n") ? text : "#{text}\n")
    end
    nil
  end

  def reopen(string = +"", mode = nil)
    return initialize(string.string, mode) if string.is_a?(StringIO)

    initialize(string, mode)
  end

  private

  def reset
    @pos = 0
    @lineno = 0
    @closed_read = false
    @closed_write = false
  end

  # `r`, `r+`, `w`, `w+`, `a` and `a+`, with the `b`, `t` and `:encoding`
  # tails a File mode may carry. A frozen buffer reads only.
  def access_mode(mode, string)
    return string.frozen? ? "r" : "r+" if mode.nil?
    return integer_mode(mode) if mode.is_a?(Integer)

    name = mode.to_str.split(":").first.to_s.delete("bt")
    raise ArgumentError, "invalid access mode #{mode}" unless READABLE[name] || WRITABLE[name]

    name
  end

  def integer_mode(bits)
    return "a+" if bits.anybits?(File::APPEND) && bits.anybits?(File::RDWR)
    return "a" if bits.anybits?(File::APPEND)
    return bits.anybits?(File::TRUNC) ? "w+" : "r+" if bits.anybits?(File::RDWR)
    return bits.anybits?(File::TRUNC) ? "w" : "w" if bits.anybits?(File::WRONLY)

    "r"
  end

  def readable!
    raise IOError, "not opened for reading" if @closed_read || !READABLE[@mode]
  end

  def writable!
    raise IOError, "not opened for writing" if @closed_write || !WRITABLE[@mode]
  end

  def rest
    text = @string.byteslice(@pos..).to_s.dup
    text.force_encoding(@external)
  end

  def put(text)
    @pos = @string.bytesize if @mode.start_with?("a")
    pad_to(@pos)
    rewrite(@pos, text.bytesize, text)
    @pos += text.bytesize
  end

  # The gap a write past the end leaves is zero bytes, as ruby's is.
  def pad_to(at)
    return if at <= @string.bytesize

    rewrite(@string.bytesize, 0, "\0" * (at - @string.bytesize))
  end

  # `count` bytes at `at` replaced by `text`, in the buffer the program
  # holds, whatever encodings the two carry.
  def rewrite(at, count, text)
    encoding = @string.encoding
    head = @string.byteslice(0, at).to_s
    tail = @string.byteslice(at + count..).to_s
    @string.replace((head.b + text.b + tail.b).force_encoding(encoding))
  end

  def unget(text)
    count = text.bytesize
    return nil if count.zero?

    if count > @pos
      rewrite(0, @pos, text)
      @pos = 0
    else
      @pos -= count
      pad_to(@pos)
      rewrite(@pos, count, text)
    end
    nil
  end

  # `gets(sep)`, `gets(limit)` and `gets(sep, limit)`.
  def line_arguments(args)
    return [$/, nil] if args.empty?
    return args[0].is_a?(Integer) ? [$/, args[0]] : [args[0]&.to_str, nil] if args.size == 1

    [args[0]&.to_str, args[1]]
  end

  def next_line(separator, limit)
    return nil if eof?

    text = rest
    text = text.byteslice(0, limit).to_s if limit
    return advance(text) if separator.nil?
    return paragraph(text) if separator.empty?

    at = text.index(separator)
    advance(at ? text.byteslice(0, at + separator.bytesize).to_s : text)
  end

  # A blank separator reads a paragraph: the run of blank lines that
  # ends it belongs to the line.
  def paragraph(text)
    text = text.sub(/\A\n+/, "")
    at = text.index("\n\n")
    advance(at ? text.byteslice(0, text[/\n\n+/, 0].then { |run| at + run.bytesize }).to_s : text)
  end

  def advance(text)
    @pos += text.bytesize
    text.dup.force_encoding(@external)
  end

  def chomp_line(line, separator)
    return line.chomp if separator.nil? || separator == $/ || separator.empty?

    line.end_with?(separator) ? line.byteslice(0, line.bytesize - separator.bytesize) : line
  end
end
