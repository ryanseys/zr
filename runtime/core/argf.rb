# frozen_string_literal: true

# ARGF: one stream over the files ARGV names, and over standard input
# when it names none. Each file opens as the walk reaches it, and the
# line numbers run on across the whole set.
# ruby's ARGF is the only instance of an unnamed class, whose report
# is the words "ARGF.class".
# `$.`: the number of the line the last read took, from any IO, or from
# ARGF, which counts across its files. Nothing has been read yet.
$. = 0

stream = Class.new do
  include Enumerable

  def initialize(argv)
    @argv = argv
    @stream = nil
    @lineno = 0
    @closed = false
    @inplace_mode = nil
  end

  attr_reader :argv, :lineno
  attr_accessor :inplace_mode

  def lineno=(n)
    @lineno = n
    $. = n
  end

  # The file being read: "-" when the walk is on standard input, which
  # is where a program with no arguments reads.
  def filename
    current
    @path || +"-"
  end

  alias path filename

  def file = current || $stdin

  def to_io = file

  def to_write_io = file

  def to_s = +"ARGF"

  def inspect = +"ARGF"

  def to_i = file.fileno
  alias fileno to_i

  def closed? = @closed

  def close
    @stream&.close unless @stream.equal?($stdin)
    @stream = nil
    @closed = true
    self
  end

  def binmode
    @binmode = true
    self
  end

  def binmode? = @binmode == true

  def external_encoding = file.external_encoding || Encoding.default_external

  def internal_encoding = file.internal_encoding

  def set_encoding(*args) = file.set_encoding(*args)

  # The walk moves to the next file when the current one runs out, so
  # every read is written the same way: read, and advance on nil.
  def gets(*args, **options)
    each_stream do |io|
      line = io.gets(*args, **options)
      next if line.nil?

      @lineno += 1
      $. = @lineno
      return line
    end
  end

  def readline(*args, **options) = gets(*args, **options) || raise(EOFError, +"end of file reached")

  def getc = each_stream { |io| (c = io.getc) and return c }

  def getbyte = each_stream { |io| (b = io.getbyte) and return b }

  def readchar = getc || raise(EOFError, +"end of file reached")

  def readbyte = getbyte || raise(EOFError, +"end of file reached")

  def read(length = nil, buffer = nil)
    text = +""
    each_stream { |io| text << io.read.to_s }
    text = text[0, length] || +"" if length
    return nil if length && text.empty?

    buffer ? buffer.replace(text) : text
  end

  def readpartial(length, buffer = nil) = read(length, buffer)
  def read_nonblock(length, buffer = nil, **) = read(length, buffer)

  def each_line(*args, **options, &block)
    return to_enum(:each_line, *args, **options) unless block

    while (line = gets(*args, **options))
      yield line
    end
    self
  end

  alias each each_line
  alias each_entry each_line

  def each_byte(&block)
    return to_enum(:each_byte) unless block

    while (byte = getbyte)
      yield byte
    end
    self
  end

  def each_char(&block)
    return to_enum(:each_char) unless block

    while (c = getc)
      yield c
    end
    self
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) unless block

    each_char { |c| yield c.ord }
  end

  def readlines(*args, **options) = each_line(*args, **options).to_a
  alias to_a readlines

  def eof?
    io = current
    io ? io.eof? && @argv.empty? : @stream.eof?
  end
  alias eof eof?

  # The current file's own position; `skip` drops it and moves on.
  def pos = file.pos
  alias tell pos

  def pos=(offset)
    file.pos = offset
  end

  def seek(offset, whence = IO::SEEK_SET) = file.seek(offset, whence)

  def rewind
    file.rewind
    @lineno = 0
    0
  end

  def skip
    @stream = nil unless @stream.equal?($stdin)
    self
  end

  def write(*texts) = file.write(*texts)
  def print(*args) = file.print(*args)
  def printf(*args) = file.printf(*args)
  def putc(c) = file.putc(c)
  def puts(*args) = file.puts(*args)

  private

  # The current stream, opening the next named file when the current
  # one ran out. A program with no arguments reads standard input;
  # one with arguments never falls back to it. A file that ran out
  # stays here closed, so a later `eof?` reports on it as ruby's
  # does.
  def current
    Primitive.attr! :hidden
    return @stream if @stream && !@stream.closed?
    return nil if @closed || (@started && @argv.empty?)

    @started = true
    @path = @argv.empty? ? +"-" : @argv.shift
    @stream = @path == +"-" ? $stdin : File.open(@path, "r")
  end

  # Runs the block on each stream in sequence, moving on when the block
  # took nothing from the current one.
  def each_stream
    Primitive.attr! :hidden
    while (io = current)
      yield io
      break if io.equal?($stdin) && @argv.empty?

      io.equal?($stdin) ? @stream = nil : io.close
    end
    nil
  end
end

stream.set_temporary_name("ARGF.class")
ARGF = stream.new(ARGV)
