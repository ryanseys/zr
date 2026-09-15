# frozen_string_literal: true

# `require "io/console"`: a terminal's modes, its size, its name, and the
# cursor escapes. ruby ships this as an extension whose rows appear at
# the require, so a program that never asks for it answers none of them.
#
# The mode itself crosses from the kernel as the bytes of struct termios,
# and the OS's layer (io/console/termios) names where its fields are and
# the flags a mode changes.
require "io/console/termios"

class IO
  # The escape introducer every cursor row writes.
  CSI = "\e["
  private_constant :CSI

  # A terminal's mode, held as the bytes tcgetattr gave. ruby names the
  # class IO::ConsoleMode and keeps the bytes to itself.
  class ConsoleMode
    def initialize_copy(other)
      Primitive.zr_hidden_set(self, :__mode__, other.__send__(:mode_bytes).dup)
      self
    end

    def echo? = (IO.send(:flag_of, mode_bytes, TERMIOS_LFLAG) & ECHO_ANY) != 0
    def echo = echo?

    def echo=(flag)
      IO.send(flag ? :echo_mode : :noecho_mode, mode_bytes, nil)
      self
    end

    def min = mode_bytes.getbyte(TERMIOS_VMIN)

    def min=(value)
      mode_bytes.setbyte(TERMIOS_VMIN, value.nil? ? 1 : IO.send(:clamp_uchar, IO.send(:int_arg, value)))
      value
    end

    # VTIME counts tenths of a second, which ruby reports exactly.
    def time = Rational(mode_bytes.getbyte(TERMIOS_VTIME), 10)

    def time=(value)
      mode_bytes.setbyte(TERMIOS_VTIME, value.nil? ? 0 : IO.send(:clamp_uchar, IO.send(:int_arg, value * 10)))
      value
    end

    # In place, and a copy under the same name without the bang.
    def raw!(**options)
      Primitive.zr_hidden_set(self, :__mode__, IO.send(:raw_mode, mode_bytes, IO.send(:raw_options, options)))
      self
    end

    def raw(**options) = dup.raw!(**options)

    def mode_bytes
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__mode__)
    end
    private :mode_bytes
  end

  # ---- the mode rows ---------------------------------------------------

  # The mode a block runs under, and the mode back as it was after it.
  # Both descriptors of a duplex handle take it. A failure here names no
  # path, because CRuby reaches these calls through a helper that holds
  # none to name.
  def ttymode(setter, options = nil)
    Primitive.attr! :hidden
    fds = console_fds
    saved = fds.map { |fd| console_mode_bytes(fd, nil) }
    fds.each_with_index { |fd, i| console_set_mode(fd, IO.send(setter, saved[i].dup, options), nil) }
    begin
      yield self
    ensure
      fds.each_with_index { |fd, i| console_set_mode(fd, saved[i], nil) }
    end
  end

  def raw(**options, &block) = ttymode(:raw_mode, IO.send(:raw_options, options), &block)

  def raw!(**options)
    # The keywords are read before the terminal is: ruby refuses a bad
    # one whatever the descriptor turns out to be.
    asked = IO.send(:raw_options, options)
    console_set_mode(console_read_fd, IO.send(:raw_mode, console_mode_bytes(console_read_fd, path), asked), path)
    self
  end

  def cooked(&block) = ttymode(:cooked_mode, &block)

  def cooked!
    console_set_mode(console_read_fd, IO.send(:cooked_mode, console_mode_bytes(console_read_fd, path), nil), path)
    self
  end

  def echo=(flag)
    bytes = console_mode_bytes(console_read_fd, path)
    console_set_mode(console_read_fd, IO.send(flag ? :echo_mode : :noecho_mode, bytes, nil), path)
    self
  end

  def echo? = (IO.send(:flag_of, console_mode_bytes(console_read_fd, path), TERMIOS_LFLAG) & ECHO_ANY) != 0

  def noecho(&block) = ttymode(:noecho_mode, &block)

  # One character, read while the terminal hands each one straight over.
  def getch(**options) = ttymode(:raw_mode, IO.send(:raw_options, options)) { getc }

  # A line read with the echo off, and a newline written after it so the
  # invisible line is left behind.
  def getpass(prompt = nil)
    target = self.equal?(STDIN) ? STDERR : self
    unless prompt.nil?
      target.write(String.try_convert(prompt) || raise(TypeError, "no implicit conversion of #{conversion_name(prompt)} into String"))
      target.flush
    end
    begin
      answer = ttymode(:noecho_mode) { gets }
    ensure
      target.write($/ || "\n")
    end
    answer&.chomp
  end

  def console_mode
    mode = ConsoleMode.allocate
    Primitive.zr_hidden_set(mode, :__mode__, console_mode_bytes(console_read_fd, path))
    mode
  end

  def console_mode=(mode)
    raise TypeError, "wrong argument type #{conversion_name(mode)} (expected IO::ConsoleMode)" unless mode.is_a?(ConsoleMode)

    console_set_mode(console_read_fd, mode.__send__(:mode_bytes), path)
    mode
  end

  # Whether a read would answer at once, which a buffer already holding
  # bytes always does.
  def input_pending?
    check_open
    buffered? || !would_block?(READABLE)
  end

  # ---- the size and the name ------------------------------------------

  def winsize
    answer = Primitive.zr_io_winsize(console_write_fd)
    raise SystemCallError.new(path, -answer) if answer.is_a?(Integer)

    answer.unpack("S<4").first(2)
  end

  # Two numbers, the rows and the columns, or four with the pixels as
  # well. Kernel#Array counts them, so a lone value counts as one.
  def winsize=(size)
    size = Array(size)
    raise ArgumentError, "wrong number of arguments (given #{size.size}, expected 2 or 4)" unless [2, 4].include?(size.size)

    fields = (size + [nil, nil]).first(4).map { |n| n.nil? ? 0 : (IO.send(:uint_arg, n) & 0xffff) }
    answer = Primitive.zr_io_set_winsize(console_write_fd, fields.pack("S<4"))
    raise SystemCallError.new(path, -answer) unless answer.zero?

    self
  end

  # The terminal's name, and nil for a descriptor that names none.
  def ttyname = Primitive.zr_io_ttyname(console_read_fd)

  def iflush
    answer = Primitive.zr_io_tcflush(console_read_fd, TCIFLUSH)
    raise SystemCallError.new(path, -answer) unless answer.zero?

    self
  end

  def oflush
    answer = Primitive.zr_io_tcflush(console_write_fd, TCOFLUSH)
    raise SystemCallError.new(path, -answer) unless answer.zero?

    self
  end

  # One queue each way on a duplex handle, and both at once when the two
  # are the same descriptor.
  def ioflush
    return iflush.oflush unless console_write_fd == console_read_fd

    answer = Primitive.zr_io_tcflush(console_read_fd, TCIOFLUSH)
    raise SystemCallError.new(path, -answer) unless answer.zero?

    self
  end

  # ---- the escapes -----------------------------------------------------

  def beep = escape("\a")

  def goto(line, column) = escape("#{CSI}#{IO.send(:shown, line)};#{IO.send(:shown, column)}H")

  def goto_column(column) = escape("#{CSI}#{IO.send(:shown, column)}G")

  def cursor_up(lines) = console_move(-IO.send(:int_arg, lines), 0)
  def cursor_down(lines) = console_move(IO.send(:int_arg, lines), 0)
  def cursor_left(columns) = console_move(0, -IO.send(:int_arg, columns))
  def cursor_right(columns) = console_move(0, IO.send(:int_arg, columns))

  def scroll_forward(lines) = console_scroll(IO.send(:int_arg, lines))
  def scroll_backward(lines) = console_scroll(-IO.send(:int_arg, lines))

  def hide_cursor = escape("#{CSI}?25l")
  def show_cursor = escape("#{CSI}?25h")

  def erase_line(mode) = escape("#{CSI}#{IO.send(:erase_arg, mode, 2, 'line')}K")
  def erase_screen(mode) = escape("#{CSI}#{IO.send(:erase_arg, mode, 3, 'screen')}J")

  def clear_screen
    erase_screen(2)
    goto(0, 0)
  end

  # The position the terminal itself reports. Anything that does not
  # answer the query in the shape ESC [ row ; column R answers nil.
  def cursor
    check_open
    write("#{CSI}6n")
    flush
    ttymode(:raw_mode) { console_read_position }
  end

  def cursor=(position)
    unless position.is_a?(Array)
      converted = Array.try_convert(position)
      raise TypeError, "no implicit conversion of #{conversion_name(position)} into Array" if converted.nil?

      position = converted
    end
    raise ArgumentError, "expected 2D coordinate" unless position.size == 2

    goto(position[0], position[1])
  end

  # Windows carries these two, and ruby says so by name here.
  def pressed?(*) = raise(NotImplementedError, "pressed?() function is unimplemented on this machine")
  def check_winsize_changed(*) = raise(NotImplementedError, "check_winsize_changed() function is unimplemented on this machine")
  def console_input_events(*) = raise(NotImplementedError, "console_input_events() function is unimplemented on this machine")

  # ---- the terminal of the process ------------------------------------

  # The controlling terminal, opened once and kept. A process that has
  # none answers nil, which is CRuby's answer as well -- it does not
  # raise. A Symbol names a row to send to the terminal instead.
  def self.console(*args)
    name = args.first
    raise TypeError, "wrong argument type #{conversion_name(name)} (expected Symbol)" unless args.empty? || name.is_a?(Symbol)

    held = Primitive.zr_hidden_get(File, :__console__)
    held = nil if held && held.closed?
    if name == :close && args.size == 1
      held&.close
      Primitive.zr_hidden_set(File, :__console__, nil)
      return nil
    end
    held ||= console_open
    return held if args.empty?
    return nil if held.nil?

    held.public_send(name, *args[1..])
  end

  # /dev/tty for reading and writing, and nil when the process has no
  # terminal to open.
  def self.console_open
    Primitive.attr! :hidden
    io = begin
      File.open("/dev/tty", "r+")
    rescue SystemCallError
      nil
    end
    return nil if io.nil?

    io.sync = true
    Primitive.zr_hidden_set(File, :__console__, io)
    io
  end

  # ---- the helpers ----------------------------------------------------

  # The descriptors a mode covers: the one a read uses, and the one a
  # write uses when a duplex handle holds two.
  def console_fds
    Primitive.attr! :hidden
    console_write_fd == console_read_fd ? [console_read_fd] : [console_read_fd, console_write_fd]
  end

  def console_read_fd
    Primitive.attr! :hidden
    fileno
  end

  def console_write_fd
    Primitive.attr! :hidden
    fileno
    Primitive.zr_hidden_get(self, :twin) || Primitive.zr_hidden_get(self, :fd)
  end

  def console_mode_bytes(fd, named)
    Primitive.attr! :hidden
    answer = Primitive.zr_io_termios(fd)
    raise SystemCallError.new(named, -answer) if answer.is_a?(Integer)

    answer
  end

  def console_set_mode(fd, bytes, named)
    Primitive.attr! :hidden
    answer = Primitive.zr_io_set_termios(fd, TCSANOW, bytes)
    raise SystemCallError.new(named, -answer) unless answer.zero?

    bytes
  end

  # Nothing at all for a distance of zero, and a flipped direction for a
  # negative one: the letter carries the direction, never a sign.
  def console_move(lines, columns)
    Primitive.attr! :hidden
    return self if lines.zero? && columns.zero?

    text = +""
    text << "#{CSI}#{lines.abs}#{lines.negative? ? 'A' : 'B'}" unless lines.zero?
    text << "#{CSI}#{columns.abs}#{columns.negative? ? 'D' : 'C'}" unless columns.zero?
    escape(text)
  end

  def console_scroll(lines)
    Primitive.attr! :hidden
    return self if lines.zero?

    escape("#{CSI}#{lines.abs}#{lines.negative? ? 'T' : 'S'}")
  end

  def escape(text)
    Primitive.attr! :hidden
    write(text)
    self
  end

  # ESC [ row ; column R, counted from one, which ruby reports counted
  # from zero.
  def console_read_position
    Primitive.attr! :hidden
    return nil unless getbyte == 0x1b && getbyte == 0x5b

    digits = +""
    digits << getbyte.chr while (0x30..0x3b).cover?(peek_position_byte)
    return nil unless getbyte == 0x52

    row, column = digits.split(";")
    return nil if column.nil?

    [row.to_i - 1, column.to_i - 1]
  end

  def peek_position_byte
    Primitive.attr! :hidden
    byte = getbyte
    ungetbyte(byte) if byte
    byte || 0
  end

  private :ttymode, :console_fds, :console_read_fd, :console_write_fd, :console_mode_bytes,
          :console_set_mode, :console_move, :console_scroll, :escape, :console_read_position,
          :peek_position_byte

  class << self
    # cfmakeraw and the three keyword arguments that follow it.
    def raw_mode(bytes, options)
      Primitive.attr! :hidden
      put_flag(bytes, TERMIOS_IFLAG, flag_of(bytes, TERMIOS_IFLAG) & ~RAW_IFLAG_OFF)
      put_flag(bytes, TERMIOS_OFLAG, flag_of(bytes, TERMIOS_OFLAG) & ~RAW_OFLAG_OFF)
      put_flag(bytes, TERMIOS_LFLAG, flag_of(bytes, TERMIOS_LFLAG) & ~RAW_LFLAG_OFF)
      put_flag(bytes, TERMIOS_CFLAG, (flag_of(bytes, TERMIOS_CFLAG) & ~RAW_CFLAG_OFF) | RAW_CFLAG_ON)
      bytes.setbyte(TERMIOS_VMIN, 1)
      bytes.setbyte(TERMIOS_VTIME, 0)
      return bytes if options.nil?

      bytes.setbyte(TERMIOS_VMIN, options[:vmin])
      bytes.setbyte(TERMIOS_VTIME, options[:vtime])
      return bytes unless options[:intr]

      put_flag(bytes, TERMIOS_IFLAG, flag_of(bytes, TERMIOS_IFLAG) | INTR_IFLAG)
      put_flag(bytes, TERMIOS_LFLAG, flag_of(bytes, TERMIOS_LFLAG) | INTR_LFLAG)
      put_flag(bytes, TERMIOS_OFLAG, flag_of(bytes, TERMIOS_OFLAG) | INTR_OFLAG)
      bytes
    end

    def cooked_mode(bytes, _options = nil)
      Primitive.attr! :hidden
      put_flag(bytes, TERMIOS_IFLAG, flag_of(bytes, TERMIOS_IFLAG) | COOKED_IFLAG_ON)
      put_flag(bytes, TERMIOS_OFLAG, flag_of(bytes, TERMIOS_OFLAG) | INTR_OFLAG)
      put_flag(bytes, TERMIOS_LFLAG, flag_of(bytes, TERMIOS_LFLAG) | COOKED_LFLAG_ON)
      bytes
    end

    def noecho_mode(bytes, _options = nil)
      Primitive.attr! :hidden
      put_flag(bytes, TERMIOS_LFLAG, flag_of(bytes, TERMIOS_LFLAG) & ~ECHO_BITS)
      bytes
    end

    def echo_mode(bytes, _options = nil)
      Primitive.attr! :hidden
      put_flag(bytes, TERMIOS_LFLAG, flag_of(bytes, TERMIOS_LFLAG) | ECHO_BITS)
      bytes
    end

    # A flag word, as wide as the OS's tcflag_t.
    def flag_of(bytes, offset)
      Primitive.attr! :hidden
      bytes.byteslice(offset, TERMIOS_FLAG_BYTES).unpack1(TERMIOS_FLAG_PACK)
    end

    def put_flag(bytes, offset, value)
      Primitive.attr! :hidden
      bytes[offset, TERMIOS_FLAG_BYTES] = [value & ((1 << (8 * TERMIOS_FLAG_BYTES)) - 1)].pack(TERMIOS_FLAG_PACK)
      bytes
    end

    # min:, time: and intr:, and nothing else. A call that names none of
    # them leaves the mode's own control characters alone.
    def raw_options(options)
      Primitive.attr! :hidden
      extra = options.keys - %i[min time intr]
      raise ArgumentError, "unknown keyword#{extra.size == 1 ? '' : 's'}: #{extra.map(&:inspect).join(', ')}" unless extra.empty?
      return nil if options.empty?

      intr = options[:intr]
      raise ArgumentError, "true or false expected as intr: #{intr}" unless intr.nil? || intr.equal?(true) || intr.equal?(false)

      { vmin: options.key?(:min) ? clamp_uchar(int_arg(options[:min])) : 1,
        vtime: options.key?(:time) ? clamp_uchar(int_arg(options[:time] * 10)) : 0,
        intr: intr.equal?(true) }
    end

    def clamp_uchar(value)
      Primitive.attr! :hidden
      value.clamp(0, 255)
    end

    # NUM2INT and NUM2UINT, whose ranges a coordinate has to fit.
    def int_arg(value)
      Primitive.attr! :hidden
      n = Primitive.zr_index_operand_m(value)
      return n if n >= -2147483648 && n <= 2147483647

      raise RangeError, "integer #{n} too #{n.negative? ? 'small' : 'big'} to convert to 'int'"
    end

    def uint_arg(value)
      Primitive.attr! :hidden
      n = Primitive.zr_index_operand_m(value)
      raise RangeError, "integer #{n} too big to convert to 'unsigned int'" if n > 4294967295
      raise RangeError, "integer #{n} too small to convert to 'unsigned int'" if n < -2147483648

      n & 0xffffffff
    end

    # The number an escape carries. CRuby counts from one inside an
    # unsigned int and prints the result as a signed one, so a position
    # of -1 comes out as 0 and -2 as -1.
    def shown(value)
      Primitive.attr! :hidden
      wrapped = (uint_arg(value) + 1) & 0xffffffff
      wrapped >= 0x80000000 ? wrapped - 0x100000000 : wrapped
    end

    def erase_arg(value, top, kind)
      Primitive.attr! :hidden
      return 0 if value.nil?
      raise ArgumentError, "wrong #{kind} erase mode: #{value}" unless value.is_a?(Integer) && value >= 0 && value <= top

      value
    end
  end
end
