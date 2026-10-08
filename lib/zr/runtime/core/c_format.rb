# frozen_string_literal: true

module Kernel
  # The format of the C API's printf functions (rb_sprintf, rb_raise,
  # rb_warn and the rest): C's printf as ruby's own (vsnprintf.c) reads
  # it. The arguments are a C call's variadic arguments, which this reads
  # in order through the call's VaList (`list`, its address) as each
  # directive asks. `%li\v` (PRIsVALUE) is a Value: with `+` its inspect,
  # with a space its text quoted when unprintable, else its to_s. The
  # result is binary until a Value's text gives it an encoding, as
  # rb_enc_vsprintf makes it.
  class CFormatter
    # The bytes of the format that this reads.
    PERCENT = 37
    STAR = 42
    DOT = 46
    VALUE_MARK = 11
    FLAGS = " #+-0".bytes.freeze
    DIGITS = (48..57)
    # The length modifiers, by the width of the integer that they read.
    # On arm64 a long, a long long, a size_t and an intmax_t are 64 bits,
    # and a long double is a double.
    SHORT = "h".bytes.freeze
    LONG = "lqztjL".bytes.freeze
    FLOATS = "fFeEgGaA".bytes.freeze
    private_constant :PERCENT, :STAR, :DOT, :VALUE_MARK, :FLAGS, :DIGITS, :SHORT, :LONG, :FLOATS

    def self.render(format, list)
      Primitive.attr! :hidden
      new(format, list).render
    end

    def initialize(format, list)
      Primitive.attr! :hidden
      @format = format
      @list = list
      # The bytes, which C's `%s` and `%c` add as they are, and the
      # encoding that the Values' texts gave them.
      @out = String.new(encoding: Encoding::BINARY)
      @encoding = Encoding::BINARY
    end

    def render
      Primitive.attr! :hidden
      at = 0
      while (percent = @format.byteindex("%", at))
        @out << @format.byteslice(at, percent - at)
        at = directive(percent + 1)
      end
      @out << @format.byteslice(at, @format.bytesize - at)
      @out.force_encoding(@encoding)
    end

    private

    # One directive, from the byte after its `%`. Returns the index after
    # it. Its flags, width, precision and integer size are the
    # formatter's state until the next one.
    def directive(at)
      Primitive.attr! :hidden
      @flags = +""
      @width = nil
      @precision = nil
      @bits = 32
      loop do
        byte = @format.getbyte(at)
        at += 1
        case byte
        when *FLAGS then @flags << byte
        when STAR then width(Primitive.zr_va_int(@list))
        when DOT
          if @format.getbyte(at) == STAR
            at += 1
            given = Primitive.zr_va_int(@list)
            @precision = given unless given.negative?
          else
            @precision, at = number(at)
          end
        when DIGITS then @width, at = number(at - 1)
        when *SHORT then @bits = 16
        when *LONG then @bits = 64
        else return conversion(byte, at)
        end
      end
    end

    # A width from `*`: a negative one is a `-` flag.
    def width(given)
      Primitive.attr! :hidden
      @flags << "-" if given.negative?
      @width = given.abs
    end

    # The digits from `at`, as a number, and the index after them.
    def number(at)
      Primitive.attr! :hidden
      n = 0
      while DIGITS.cover?(byte = @format.getbyte(at))
        n = (n * 10) + byte - 48
        at += 1
      end
      [n, at]
    end

    # Writes the argument of the conversion `byte`, at `at` in the format.
    # Returns the index after the directive.
    def conversion(byte, at)
      Primitive.attr! :hidden
      spec = "%#{@flags}#{@width}#{".#{@precision}" if @precision}"
      case byte.chr
      when "i"
        if @bits == 64 && @format.getbyte(at) == VALUE_MARK
          value(Primitive.zr_va_value(@list))
          return at + 1
        end
        @out << format("#{spec}d", signed)
      when "d" then @out << format("#{spec}d", signed)
      when "u", "o", "x", "X"
        # An unsigned number has no sign to show.
        @out << format("#{spec.delete("+ ")}#{byte == 117 ? "d" : byte.chr}", unsigned(@bits))
      when "c" then pad(unsigned(8).chr)
      when "s" then pad(text(Primitive.zr_va_cstr(@list)))
      when "p" then pad(format("0x%016x", unsigned(64)))
      when "%" then @out << "%"
      else
        raise ArgumentError, "malformed format string - %#{byte.chr}" unless FLOATS.include?(byte)

        # Ruby's format has no %F; C's differs only for inf and nan.
        @out << format("#{spec}#{byte == 70 ? "f" : byte.chr}", Primitive.zr_va_double(@list))
      end
      at
    end

    # The next argument as a signed integer of the directive's size.
    def signed
      Primitive.attr! :hidden
      n = unsigned(@bits)
      n >= 1 << (@bits - 1) ? n - (1 << @bits) : n
    end

    # The next argument as an unsigned integer of `bits`: C passes an int
    # or a short in a whole word, whose high bits mean nothing.
    def unsigned(bits)
      Primitive.attr! :hidden
      Primitive.zr_va_word(@list) & ((1 << bits) - 1)
    end

    # A C string, or `(null)` for NULL, cut to the precision in bytes.
    def text(string)
      Primitive.attr! :hidden
      string ||= "(null)".b
      @precision ? string.byteslice(0, @precision) : string
    end

    # ruby__sfvextra: the text of a Value, in the result's encoding.
    def value(object)
      Primitive.attr! :hidden
      shown = if @flags.include?("+")
                object.inspect
              elsif object.is_a?(Symbol)
                @flags.include?(" ") && object.inspect.start_with?(":\"") ? object.name.send(:escape) : object.name
              else
                Primitive.zr_obj_as_string(object).then { |s| @flags.include?(" ") ? s.send(:quote_unprintable) : s }
              end
      if (encoding = Encoding.compatible?(@out.dup.force_encoding(@encoding), shown))
        @encoding = encoding
      else
        shown = shown.encode(@encoding, invalid: :replace, undef: :replace)
      end
      pad(text(shown.b))
    end

    # Appends the bytes of `text`, padded with spaces to the width: on the
    # right for `-`.
    def pad(text)
      Primitive.attr! :hidden
      room = @width.to_i - text.bytesize
      left = @flags.include?("-")
      @out << (" " * room) if room.positive? && !left
      @out << text
      @out << (" " * room) if room.positive? && left
    end
  end

  private_constant :CFormatter
end
