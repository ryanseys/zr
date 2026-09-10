# IO: a file descriptor with a read buffer. Writes go straight to the
# descriptor. `Kernel#puts` and friends write to whatever `$stdout`
# is, as CRuby's do.
class IO
  include Enumerable

  SEEK_SET = 0
  SEEK_CUR = 1
  SEEK_END = 2
  NULL = "/dev/null"

  # A pipe's read and write ends, closed after the block when one is
  # given.
  def self.pipe
    ends = Primitive.zr_io_pipe
    raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

    reader = IO.new(ends[0], "r")
    writer = IO.new(ends[1], "w")
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

  def self.try_convert(object) = object.respond_to?(:to_io) ? object.to_io : nil

  # Everything one stream holds, written to the other.
  def self.copy_stream(from, to, length = nil, offset = nil)
    text = from.is_a?(IO) ? from.read(length) : File.read(from, length, offset)
    to.is_a?(IO) ? to.write(text) : File.write(to, text)
  end

  def initialize(fd, mode = "r", path: nil, name: nil)
    @fd = fd
    @mode = mode
    @path = path
    @name = name
    @closed = false
    @sync = false
    @lineno = 0
    @buffer = +""
    @eof = false
  end

  attr_reader :lineno

  def path = @path || @name
  attr_accessor :sync

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

    @closed = true
    result = @fd > 2 ? Primitive.zr_io_close(@fd) : 0
    raise SystemCallError.new("@ rb_io_close - #{label}", -result) if result < 0

    nil
  end

  def flush
    check_open
    self
  end

  def fsync
    check_open
    Primitive.zr_io_fsync(@fd)
    0
  end

  def binmode = self

  def binmode? = false

  def fdatasync = fsync

  def to_path = path

  def stat = File.stat(path)

  # A pipe's other end has no pid here: nothing forks behind an IO.
  def pid = nil

  def autoclose? = @fd > 2

  def autoclose=(flag)
    flag
  end

  # A descriptor ruby opens closes itself across an exec.
  def close_on_exec? = true

  def close_on_exec=(flag)
    flag
  end

  def close_read = close

  def close_write = close

  def each_codepoint(&block)
    return to_enum(:each_codepoint) unless block

    read.each_codepoint(&block)
    self
  end

  alias codepoints each_codepoint

  # `pread` and `pwrite` leave the descriptor's own offset alone.
  def pread(length, offset, buffer = nil)
    here = seek(0, SEEK_CUR)
    begin
      seek(offset, SEEK_SET)
      text = read(length)
      raise EOFError, "end of file reached" if text.nil?

      buffer ? buffer.replace(text) : text
    ensure
      seek(here, SEEK_SET)
    end
  end

  def pwrite(text, offset)
    here = seek(0, SEEK_CUR)
    begin
      seek(offset, SEEK_SET)
      write(text)
    ensure
      seek(here, SEEK_SET)
    end
  end

  def sysseek(offset, whence = SEEK_SET) = seek(offset, whence)

  def external_encoding = @mode.start_with?("r") || @mode.include?("+") ? Encoding.default_external : nil

  def internal_encoding = nil

  def set_encoding(*) = self

  def inspect
    text = "#<#{self.class}:#{label}"
    text = "#{text} (closed)" if @closed
    "#{text}>"
  end

  def write(*objects)
    check_writable
    total = 0
    objects.each do |object|
      s = object.to_s
      result = Primitive.zr_io_write(@fd, s)
      raise SystemCallError.new("@ io_write - #{label}", -result) if result < 0

      total += result
    end
    total
  end

  def syswrite(text) = write(text)

  def <<(object)
    write(object)
    self
  end

  def print(*objects)
    objects.each { |object| write(object.to_s) }
    nil
  end

  def puts(*objects)
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
        lines_of(object).then { |lines| object.empty? ? [] : lines }
      else
        text = object.to_s
        text = object.inspect unless text.is_a?(String)
        text.end_with?("\n") ? [text] : [text + "\n"]
      end
    end
  end

  def printf(format, *args)
    write(Kernel.format(format, *args))
    nil
  end

  def p(*objects)
    objects.each { |object| write(object.inspect, "\n") }
    objects.size <= 1 ? objects[0] : objects
  end

  # `read(length)`: that many bytes, fewer at the end, nil past it;
  # without a length, everything that is left.
  def read(length = nil, buffer = nil)
    check_readable
    raise ArgumentError, "negative length #{length} given" if length && length < 0

    if length.nil?
      fill until @eof
      out = @buffer
      @buffer = +""
    else
      fill while !@eof && @buffer.bytesize < length
      return length == 0 ? +"" : nil if @buffer.empty? && length > 0

      out = @buffer.byteslice(0, length)
      @buffer = @buffer.byteslice(length, @buffer.bytesize - length) || +""
    end
    buffer ? buffer.replace(out) : out
  end

  def sysread(length) = read(length) || raise(EOFError, "end of file reached")

  def readpartial(length) = read(length) || raise(EOFError, "end of file reached")

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

  def ungetc(text)
    @buffer = text.to_s + @buffer
    nil
  end

  alias ungetbyte ungetc

  # A line up to and with `separator`; "" separates paragraphs; nil
  # reads to the end. `limit` caps the bytes.
  def gets(separator = $/, limit = nil, chomp: false)
    check_readable
    separator, limit = $/, separator if separator.is_a?(Integer)
    line = read_line(separator, limit)
    $_ = nil
    return nil if line.nil?

    @lineno += 1
    $_ = chomp ? chomp_line(line, separator) : line
  end

  def readline(*args, **options)
    gets(*args, **options) || raise(EOFError, "end of file reached")
  end

  def each_line(separator = $/, limit = nil, chomp: false)
    return to_enum(:each_line, separator, limit, chomp: chomp) unless block_given?

    while (line = gets(separator, limit, chomp: chomp))
      yield line
    end
    self
  end

  alias each each_line

  def readlines(separator = $/, limit = nil, chomp: false)
    each_line(separator, limit, chomp: chomp).to_a
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
    result = Primitive.zr_io_seek(@fd, 0, SEEK_CUR)
    raise SystemCallError.new("@ rb_io_tell - #{label}", -result) if result < 0

    result - @buffer.bytesize
  end

  alias tell pos

  def seek(offset, whence = SEEK_SET)
    check_open
    whence = { set: SEEK_SET, cur: SEEK_CUR, end: SEEK_END }.fetch(whence) if whence.is_a?(Symbol)
    offset -= @buffer.bytesize if whence == SEEK_CUR
    @buffer = +""
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

  def check_readable
    Primitive.attr! :hidden
    check_open
    raise IOError, "not opened for reading" if @mode.start_with?("w", "a") && !@mode.include?("+")
  end

  def check_writable
    Primitive.attr! :hidden
    check_open
    raise IOError, "not opened for writing" if @mode.start_with?("r") && !@mode.include?("+")
  end

  # More bytes into the buffer; none marks the end.
  def fill
    Primitive.attr! :hidden
    chunk = Primitive.zr_io_read(@fd, 8192)
    if chunk.nil?
      @eof = true
    elsif chunk.is_a?(Integer)
      raise SystemCallError.new("@ io_fillbuf - #{label}", -chunk)
    else
      @buffer << chunk
    end
  end

  def read_line(separator, limit)
    Primitive.attr! :hidden
    if separator.nil?
      fill until @eof
      return nil if @buffer.empty?

      return take(limit ? [limit, @buffer.bytesize].min : @buffer.bytesize)
    end
    paragraph = separator.empty?
    separator = "\n\n" if paragraph
    if paragraph
      fill while !@eof && @buffer.start_with?("\n")
      @buffer = @buffer.byteslice(1, @buffer.bytesize - 1) || +"" while @buffer.start_with?("\n")
    end
    loop do
      at = @buffer.index(separator)
      if at
        stop = at + separator.bytesize
        stop = [stop, limit].min if limit
        line = take(stop)
        if paragraph
          fill while !@eof && @buffer.start_with?("\n")
          @buffer = @buffer.byteslice(1, @buffer.bytesize - 1) || +"" while @buffer.start_with?("\n")
        end
        return line
      end
      return take([limit, @buffer.bytesize].min) if limit && @buffer.bytesize >= limit
      break if @eof

      fill
    end
    return nil if @buffer.empty?

    take(@buffer.bytesize)
  end

  def take(n)
    Primitive.attr! :hidden
    out = @buffer.byteslice(0, n)
    @buffer = @buffer.byteslice(n, @buffer.bytesize - n) || +""
    out
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

  def print(*objects)
    out = $stdout
    objects.each { |object| out.write(object.to_s) }
    nil
  end

  def p(*objects)
    out = $stdout
    objects.each do |object|
      out.write(object.inspect)
      out.write("\n")
    end
    objects.size <= 1 ? objects[0] : objects
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

  def gets(*args, **options) = $stdin.gets(*args, **options)

  def readline(*args, **options) = $stdin.readline(*args, **options)

  def readlines(*args, **options) = $stdin.readlines(*args, **options)

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
end

module Errno
  CODES = { EPERM: 1, ENOENT: 2, ESRCH: 3, EINTR: 4, EIO: 5, ENXIO: 6, E2BIG: 7, ENOEXEC: 8, EBADF: 9, ECHILD: 10,
            EDEADLK: 11, ENOMEM: 12, EACCES: 13, EFAULT: 14, EBUSY: 16, EEXIST: 17, EXDEV: 18, ENODEV: 19, ENOTDIR: 20,
            EISDIR: 21, EINVAL: 22, ENFILE: 23, EMFILE: 24, ENOTTY: 25, EFBIG: 27, ENOSPC: 28, ESPIPE: 29, EROFS: 30,
            EMLINK: 31, EPIPE: 32, EDOM: 33, ERANGE: 34, EAGAIN: 35, EINPROGRESS: 36, EALREADY: 37, ENOTSOCK: 38,
            EADDRINUSE: 48, EADDRNOTAVAIL: 49, ENETUNREACH: 51, ECONNRESET: 54, ENOTCONN: 57, ETIMEDOUT: 60,
            ECONNREFUSED: 61, ELOOP: 62, ENAMETOOLONG: 63, EHOSTUNREACH: 65, ENOTEMPTY: 66, ENOSYS: 78 }.freeze
  private_constant :CODES

  CODES.each do |name, code|
    klass = Class.new(SystemCallError)
    klass.const_set(:Errno, code)
    const_set(name, klass)
  end
  EWOULDBLOCK = EAGAIN

  def self.for(code) = CODES.key(code)&.then { |name| const_get(name) }

  def self.text(code)
    message = Primitive.zr_io_strerror(code)
    message.start_with?("Unknown error") ? "Unknown error: #{code}" : message
  end
end
