# frozen_string_literal: true

# ARGF: one stream over the files ARGV names, and over standard input
# when it names none. This follows io.c's ARGF: argf_next_argv opens
# each file as the walk reaches it, a read that ends a file closes it
# and moves on, and the line numbers run on across the whole set.
# ruby's ARGF is the only instance of an unnamed class, whose report
# is the words "ARGF.class".
# `$.`: the number of the line the last read took, from any IO, or from
# ARGF, which counts across its files. Nothing has been read yet.
$. = 0

stream = Class.new do
  include Enumerable

  # argf_initialize: an ARGF.class of its own reads the files it is given.
  def initialize(*argv) = start(argv)

  # The program's ARGF starts on ARGV itself, so it sees a change to ARGV.
  # `@init` and `@next` are io.c's init_p and next_p: 0 before the first
  # read and -1 after a close, then 1; and 1 to open the next name, 0
  # while a file is open, -1 on standard input.
  private def start(argv)
    @argv = argv
    @filename = nil
    @current = nil
    @lineno = 0
    @init = 0
    @next = 0
    @binmode = false
    @encodings = nil
    @inplace_mode = nil
    @write_io = nil
    self
  end

  attr_reader :argv, :lineno

  # argf_inplace_mode_get: nil when ARGF does not edit in place, "" when
  # it edits with no backup, or the backup's extension.
  def inplace_mode = @inplace_mode&.dup

  # argf_inplace_mode_set: a false value stops the edit in place.
  def inplace_mode=(ext)
    unless ext
      @inplace_mode = nil
      return
    end

    text = String.try_convert(ext)
    raise TypeError, no_implicit_conversion(ext, "String") if text.nil?
    # StringValueCStr: a NUL character, which in UTF-16 or UTF-32 is not
    # a NUL byte alone.
    nul = Encoding.wide?(text.encoding) ? text.each_char.any? { |c| c.ord.zero? } : text.b.include?("\0")
    raise ArgumentError, +"string contains null byte" if nul

    @inplace_mode = text.dup.freeze
  end

  # argf_initialize_copy: a copy reads on its own, from a copy of the
  # names that are left.
  def initialize_copy(orig)
    super
    @argv = @argv.dup
  end

  # argf_set_lineno: `$.` is the program's ARGF's last line number, so
  # another ARGF leaves it alone.
  def lineno=(n)
    @lineno = Integer.send(:int_operand, n)
    $. = @lineno if equal?(ARGF)
  end

  # argf_lineno_setter: an assignment to `$.` sets the line number of the
  # program's ARGF too.
  def lineno_assigned(n)
    Primitive.attr! :hidden
    @lineno = n
  end

  def filename
    next_argv
    @filename
  end

  alias path filename

  def file
    next_argv
    @current
  end

  def to_io
    next_argv
    return @current if generic?

    @current
  end

  def to_write_io
    raise IOError, +"not opened for writing" unless @current

    @write_io || @current
  end

  def to_s = +"ARGF"

  alias inspect to_s

  def fileno
    raise ArgumentError, +"no stream" unless next_argv
    return @current.fileno if generic?

    @current.fileno
  end

  alias to_i fileno

  def closed?
    next_argv
    @current.closed?
  end

  # argf_close_m: the current file closes, the next read takes the next
  # name, and the line numbers start again.
  def close
    next_argv
    close_current
    @next = 1 unless @next == -1
    @lineno = 0
    self
  end

  # argf_skip: the rest of the current file goes unread.
  def skip
    if @init.nonzero? && @next.zero?
      close_current
      @next = 1
    end
    self
  end

  def binmode
    @binmode = true
    next_argv
    @current.binmode unless generic?
    self
  end

  def binmode? = @binmode

  def external_encoding = @current ? @current.external_encoding : Encoding.default_external

  def internal_encoding = @current ? @current.internal_encoding : Encoding.default_external

  # argf_set_encoding: the encodings hold for each file the walk opens.
  def set_encoding(*args, **options)
    raise ArgumentError, +"no stream to set encoding" unless next_argv

    @current.set_encoding(*args, **options)
    @encodings = [@current.external_encoding, @current.internal_encoding]
    self
  end

  # argf_getline: a file that runs out closes, and the next one goes on.
  def gets(*args, **options)
    while true
      return nil unless next_argv

      line = @current.gets(*args, **options)
      if line.nil? && @next != -1 && !generic?
        close_current
        @next = 1
        next
      end
      unless line.nil?
        @lineno += 1
        $. = @lineno if equal?(ARGF)
      end
      return line
    end
  end

  def readline(*args, **options) = gets(*args, **options) || raise(EOFError, +"end of file reached")

  def getc = each_read(:getc)

  def getbyte = each_read(:getbyte)

  def readchar = getc || raise(EOFError, +"end of file reached")

  def readbyte = getbyte || raise(EOFError, +"end of file reached")

  # argf_read: a length reads on into the next files until it is met;
  # none reads every file.
  def read(length = nil, buffer = nil)
    length = Integer.send(:int_operand, length) unless length.nil?
    unless buffer.nil?
      buffer = Primitive.zr_str_operand(buffer)
      buffer.clear
    end
    text = buffer
    while true
      return text unless next_argv

      want = length && (length - (text ? text.bytesize : 0))
      piece = want ? @current.read(want) : @current.read
      if text.nil?
        text = piece
      elsif piece
        text << piece
      end
      if piece.nil? || length.nil?
        break if @next == -1

        close_current
        @next = 1
        next
      end
      break if text.bytesize >= length
    end
    text
  end

  # argf_getpartial: what the current file has; its end is an empty
  # String while more files follow, and EOFError after the last.
  def readpartial(length, buffer = nil) = partial(length, buffer, false, true)

  def read_nonblock(length, buffer = nil, exception: true) = partial(length, buffer, true, exception)

  def each_line(*args, **options)
    return to_enum(:each_line, *args, **options) unless block_given?

    while next_argv
      counted = @current.lineno
      current = @current
      broke = false
      @current.each_line(*args, **options) do |line|
        # The program's ARGF counts the lines its file counts; another
        # counts every piece, and leaves `$.` alone.
        if !equal?(ARGF)
          @lineno += 1
        elsif @current.lineno != counted
          counted = @current.lineno
          @lineno += 1
          $. = @lineno
        end
        yield line
        # argf_block_call_i: a block that closed or skipped the file, or
        # moved ARGF to another, ends this file's walk.
        if @init == -1 || !current.equal?(@current)
          broke = true
          break
        end
      end
      @next = 1 unless broke
    end
    self
  end

  alias each each_line

  def each_byte(&block) = each_part(:each_byte, &block)

  def each_char(&block) = each_part(:each_char, &block)

  def each_codepoint(&block) = each_part(:each_codepoint, &block)

  # argf_readlines: every file's lines, each file closed after them.
  def readlines(*args, **options)
    lineno = @lineno
    lines = []
    while next_argv
      lines.concat(@current.readlines(*args, **options))
      close_current unless generic?
      @next = 1
      @lineno = lineno + lines.size
      $. = @lineno if equal?(ARGF)
    end
    @init = 0
    lines
  end

  alias to_a readlines

  # argf_eof: at the end of the current file, before the walk moves on.
  def eof?
    next_argv
    return false unless @current
    return true if @init.zero?

    next_argv
    @current.eof?
  end

  alias eof eof?

  def pos
    raise ArgumentError, +"no stream to tell" unless next_argv

    @current.pos
  end

  alias tell pos

  def pos=(offset)
    raise ArgumentError, +"no stream to set position" unless next_argv

    @current.pos = offset
  end

  def seek(offset, whence = IO::SEEK_SET)
    raise ArgumentError, +"no stream to seek" unless next_argv

    @current.seek(offset, whence)
  end

  # argf_rewind: the lines of the current file no longer count.
  def rewind
    raise ArgumentError, +"no stream to rewind" unless next_argv

    before = @current.lineno
    result = @current.rewind
    # The program's ARGF keeps `$.`; another ARGF never sets it.
    @lineno -= before
    result
  end

  def write(*texts) = to_write_io.write(*texts)
  def print(*args) = to_write_io.print(*args)
  def printf(*args) = to_write_io.printf(*args)
  def putc(c) = to_write_io.putc(c)
  def puts(*args) = to_write_io.puts(*args)

  private

  # ARGF_GENERIC_INPUT_P: standard input that is not an IO, which ARGF
  # reads through its own methods.
  def generic?
    Primitive.attr! :hidden
    @current.equal?($stdin) && !$stdin.is_a?(IO)
  end

  # argf_next_argv: whether there is a stream to read, opening the next
  # name when the last one ran out. With no names, it is standard input.
  def next_argv
    Primitive.attr! :hidden
    if @init.zero?
      @next = @argv && !@argv.empty? ? 1 : -1
      @init = 1
    elsif @argv.nil?
      @next = -1
    elsif @next == -1 && !@argv.empty?
      @next = 1
    end
    if @next == 1
      close_current if @init == 1
      # Not `loop`, whose frame a backtrace would show.
      opened = false
      until opened
        if @argv.empty?
          @next = 1
          return false
        end
        name = File.send(:path_of, @argv.shift)
        @filename = name
        if name == +"-"
          @current = $stdin
          opened = !@inplace_mode
          Primitive.zr_warn_here_m(+"Can't do inplace edit for stdio; skipping") unless opened
        else
          @current = File.open(name, "r")
          opened = !@inplace_mode || edit_in_place(name)
        end
      end
      @current.binmode if @binmode && !generic?
      @current.set_encoding(*@encodings) if @encodings && !generic?
      @next = 0
    elsif @next == -1
      @current = $stdin
      @filename = +"-"
      if @inplace_mode
        Primitive.zr_warn_here_m(+"Can't do inplace edit for stdio")
        $stdout = STDOUT
      end
    end
    @init = 1 if @init == -1
    true
  end

  # The file that ARGF opened, `name`, edited in place (-i): it moves to
  # its backup name, or goes when there is no backup, and $stdout writes a
  # new file of that name, with the old file's mode. The file that
  # $stdout wrote before closes. Warns and returns false to skip a file
  # that cannot move.
  def edit_in_place(name)
    Primitive.attr! :hidden
    out = $stdout
    out.close if out.is_a?(IO) && !out.equal?(STDOUT) && !out.closed?
    mode = @current.stat.mode
    begin
      if @inplace_mode.empty?
        File.unlink(name)
      else
        File.rename(name, backup_name(name))
      end
    rescue SystemCallError => e
      why = @inplace_mode.empty? ? "Can't remove #{name}" : "Can't rename #{name} to #{backup_name(name).dup.force_encoding(name.encoding)}"
      Primitive.zr_warn_here_m("#{why}: #{e.message.sub(/ @ .*\z/m, "")}, skipping file")
      @current.close
      return false
    end
    write = File.open(name, File::WRONLY | File::CREAT | File::TRUNC, 0o666)
    write.chmod(mode)
    $stdout = @write_io = write
    true
  end

  # The backup's name: the suffix converted to the name's encoding, as
  # rb_str_cat_conv_enc_opts appends it, or its bytes when it cannot be.
  def backup_name(name)
    Primitive.attr! :hidden
    suffix = begin
      @inplace_mode.encode(name.encoding)
    rescue EncodingError
      return name.b + @inplace_mode.b
    end
    (name.b + suffix.b).force_encoding(name.encoding)
  end

  # argf_close: the current file closes; standard input stays open. The
  # file that an edit in place writes stays $stdout until the next file.
  def close_current
    Primitive.attr! :hidden
    @write_io = nil
    return if @current.nil? || @current.equal?($stdin)

    @current.close unless @current.closed?
    @init = -1
  end

  # A read of one character or byte, which moves on at a file's end.
  def each_read(name)
    Primitive.attr! :hidden
    while true
      return nil unless next_argv

      got = @current.public_send(name)
      if got.nil? && @next != -1 && !generic?
        close_current
        @next = 1
        next
      end
      return got
    end
  end

  # FOREACH_ARGF: each file's own iterator, then the next file.
  def each_part(name, &block)
    Primitive.attr! :hidden
    return to_enum(name) unless block

    while next_argv
      current = @current
      broke = false
      @current.public_send(name) do |part|
        yield part
        # argf_block_call_i: a block that closed or skipped the file, or
        # moved ARGF to another, ends this file's walk.
        if @init == -1 || !current.equal?(@current)
          broke = true
          break
        end
      end
      @next = 1 unless broke
    end
    self
  end

  def partial(length, buffer, nonblock, exception)
    Primitive.attr! :hidden
    buffer = Primitive.zr_str_operand(buffer) unless buffer.nil?
    unless next_argv
      buffer&.clear
      raise EOFError, +"end of file reached"
    end
    got = begin
      nonblock ? @current.read_nonblock(length, buffer, exception: exception) : @current.readpartial(length, buffer)
    rescue EOFError
      nil
    end
    return got unless got.nil?
    return partial_end(exception) if @next == -1

    close_current
    @next = 1
    return partial_end(exception) if @argv.empty?

    buffer || +""
  end

  def partial_end(exception)
    Primitive.attr! :hidden
    raise EOFError, +"end of file reached" if exception

    nil
  end
end

stream.set_temporary_name("ARGF.class")
ARGF = stream.allocate.send(:start, ARGV)
