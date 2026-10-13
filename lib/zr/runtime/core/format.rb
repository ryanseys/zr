# frozen_string_literal: true

# `Kernel#format` over Integer, Float, String, Symbol and the `%c` and
# `%p` directives.
module Kernel
  # format and sprintf are two methods, as in ruby, so a backtrace names
  # the one that the program called.
  def format(*args) = Kernel.formatted(args)

  def sprintf(*args) = Kernel.formatted(args)

  # The spec and its arguments, rendered. Its frame is hidden: a
  # backtrace shows the caller (format, sprintf or String#%) alone.
  def self.formatted(args)
    Primitive.attr! :hidden
    raise ArgumentError, +"too few arguments" if args.empty?

    Formatter.new(Primitive.zr_str_operand(args.first), args.drop(1)).render
  end

  private :format, :sprintf

  # One `format` call: walks the spec's bytes, taking arguments in
  # order, by position (`%1$d`) or by name (`%<n>d`, `%{n}`). Its
  # methods are hidden helpers: a backtrace shows the caller alone.
  class Formatter
    # The bits of sprintf.c's `flags`: the five flag characters, then
    # whether a width, a precision, and a `.` were given.
    FSHARP = 1
    FMINUS = 2
    FPLUS = 4
    FZERO = 8
    FSPACE = 16
    FWIDTH = 32
    FPREC = 64
    FPREC0 = 128
    FLAG_BITS = { 32 => FSPACE, 35 => FSHARP, 43 => FPLUS, 45 => FMINUS, 48 => FZERO }.freeze
    CONVERSIONS = "csp{diouxXbBfeEgGaA".bytes.freeze
    # No value was taken yet for a directive.
    NONE = Object.new.freeze
    private_constant :FSHARP, :FMINUS, :FPLUS, :FZERO, :FSPACE, :FWIDTH, :FPREC, :FPREC0, :FLAG_BITS, :CONVERSIONS, :NONE

    def initialize(spec, args)
      Primitive.attr! :hidden
      encoding = Encoding.at(Primitive.zr_str_encoding_index_m(spec))
      raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{encoding}" unless encoding.ascii_compatible?

      # A subclass's text is read as its bytes, as rb_str_format reads it.
      @spec = Primitive.zr_real_class(spec).equal?(String) ? spec : String.new(spec)
      @args = args
      # sprintf.c's `posarg`: 0 before any argument, the last unnumbered
      # one taken, -1 after a numbered one, -2 after a named one.
      @posarg = 0
      @nextarg = 1
      @hash = nil
      @out = "".dup.force_encoding(@spec.encoding)
    end

    def render
      Primitive.attr! :hidden
      i = 0
      size = @spec.bytesize
      while i < size
        b = @spec.getbyte(i)
        if b != 37
          @out << @spec.byteslice(i, 1)
          i += 1
          next
        end
        raise ArgumentError, +"incomplete format specifier; use %% (double %) instead" if i + 1 == size

        i = directive(i + 1)
      end
      too_many
      @out
    end

    private

    # rb_str_format's `retry` loop over one directive, from the byte after
    # its `%`. Returns the index after the directive.
    def directive(i)
      Primitive.attr! :hidden
      flags = 0
      fl = +""
      width = 0
      prec = 0
      value = NONE
      sym = nil
      while true
        b = i < @spec.bytesize ? @spec.getbyte(i) : 0
        if (bit = FLAG_BITS[b])
          raise ArgumentError, +"flag after width" if flags & FWIDTH != 0
          raise ArgumentError, +"flag after precision" if flags & FPREC0 != 0

          flags |= bit
          fl << Primitive.zr_str_from_byte(b)
          i += 1
        elsif b >= 49 && b <= 57
          n, i = get_num(i, "width")
          if @spec.getbyte(i) == 36
            raise ArgumentError, "value given twice - #{n}$" unless value.equal?(NONE)

            value = pos_arg(n)
            i += 1
          else
            width_check(flags)
            width = n
            flags |= FWIDTH
          end
        elsif b == 60 || b == 123
          term = b == 60 ? 62 : 125
          stop = i
          stop += 1 while stop < @spec.bytesize && @spec.getbyte(stop) != term
          raise ArgumentError, +"malformed name - unmatched parenthesis" if stop >= @spec.bytesize

          text = @spec.byteslice(i, stop - i + 1)
          raise ArgumentError, "named#{text} after <#{sym}>" if sym

          raise ArgumentError, "named#{text} after unnumbered(#{@posarg})" if @posarg > 0
          raise ArgumentError, "named#{text} after numbered" if @posarg == -1

          @posarg = -2
          hash = one_hash
          sym = @spec.byteslice(i + 1, stop - i - 1).to_sym
          value = if hash.key?(sym)
                    hash[sym]
                  else
                    found = Primitive.zr_hash_default(hash, sym)
                    raise KeyError.new("key#{text} not found", receiver: hash, key: sym) if found.nil?

                    found
                  end
          if term == 125
            @out << convert(115, value, fl, flags & FWIDTH != 0 ? width : nil, flags & FPREC != 0 ? prec : nil)
            return stop + 1
          end
          i = stop + 1
        elsif b == 42
          width_check(flags)
          flags |= FWIDTH
          width, i = aster(i, "width")
          if width < 0
            flags |= FMINUS
            fl << "-"
            width = -width
            # An int has no room for -INT_MIN.
            raise ArgumentError, +"width too big" if width > 2_147_483_647
          end
        elsif b == 46
          raise ArgumentError, +"precision given twice" if flags & FPREC0 != 0

          flags |= FPREC | FPREC0
          prec = 0
          i += 1
          if @spec.getbyte(i) == 42
            # GETASTER names it by its variable.
            prec, i = aster(i, "prec")
            flags &= ~FPREC if prec < 0
          else
            prec, i = get_num(i, "precision")
          end
        elsif b == 37
          raise ArgumentError, +"invalid format character - %" if flags != 0

          @out << "%"
          return i + 1
        elsif Primitive.zr_table_member_p(CONVERSIONS, b)
          value = next_arg if value.equal?(NONE)
          @out << convert(b, value, fl, flags & FWIDTH != 0 ? width : nil, flags & FPREC != 0 ? prec : nil)
          return i + 1
        elsif b >= 32 && b <= 126
          raise ArgumentError, "malformed format string - %#{Primitive.zr_str_from_byte(b)}"
        else
          raise ArgumentError, +"malformed format string"
        end
      end
    end

    # get_num: the digits from `i`, which must not run to the end.
    def get_num(i, what)
      Primitive.attr! :hidden
      n = 0
      while i < @spec.bytesize && (digit = @spec.getbyte(i)) >= 48 && digit <= 57
        n = n * 10 + (digit - 48)
        raise ArgumentError, "#{what} too big" if n > 2_147_483_647

        i += 1
      end
      raise ArgumentError, +"malformed format string - %*[0-9]" if i >= @spec.bytesize

      [n, i]
    end

    # GETASTER at the `*` at `i`: `*n$` takes argument n, a bare `*` the
    # next one. Returns the Integer and the index after the `*` form.
    def aster(i, what)
      Primitive.attr! :hidden
      n, after = get_num(i + 1, what)
      if @spec.getbyte(after) == 36
        v = pos_arg(n)
        i = after
      else
        v = next_arg
      end
      [num2int(v), i + 1]
    end

    # NUM2INT: a width or precision must fit in a C int.
    def num2int(v)
      Primitive.attr! :hidden
      raise TypeError, no_implicit_conversion(v, "Integer") if nil.equal?(v)
      if Float === v
        raise RangeError, "float #{Kernel.format("%-.10g", v)} out of range of integer" unless v >= -2**63 && v < 2**63

        v = v.to_i
      end
      n = Primitive.zr_index_operand_m(v)
      raise RangeError, "integer #{n} too big to convert to 'int'" if n > 2_147_483_647
      raise RangeError, "integer #{n} too small to convert to 'int'" if n < -2_147_483_648

      n
    end

    # GETNEXTARG: an argument in order, unless a numbered or a named one
    # came before.
    def next_arg
      Primitive.attr! :hidden
      raise ArgumentError, "unnumbered(#{@nextarg}) mixed with numbered" if @posarg == -1
      raise ArgumentError, "unnumbered(#{@nextarg}) mixed with named" if @posarg == -2

      @posarg = @nextarg
      @nextarg += 1
      nth(@posarg)
    end

    # GETPOSARG: argument `n`, counted from 1.
    def pos_arg(n)
      Primitive.attr! :hidden
      raise ArgumentError, "numbered(#{n}) after unnumbered(#{@posarg})" if @posarg > 0
      raise ArgumentError, "numbered(#{n}) after named" if @posarg == -2
      raise ArgumentError, "invalid index - #{n}$" if n < 1

      @posarg = -1
      nth(n)
    end

    def nth(n)
      Primitive.attr! :hidden
      raise ArgumentError, +"too few arguments" if n > @args.size

      @args[n - 1]
    end

    # get_hash: the one argument, as a Hash (to_hash).
    def one_hash
      Primitive.attr! :hidden
      return @hash if @hash
      raise ArgumentError, +"one hash required" unless @args.size == 1

      @hash = Hash.try_convert(@args[0]) or raise ArgumentError, +"one hash required"
    end

    def width_check(flags)
      Primitive.attr! :hidden
      raise ArgumentError, +"width given twice" if flags & FWIDTH != 0
      raise ArgumentError, +"width after precision" if flags & FPREC0 != 0
    end

    # sprint_exit: arguments in order that the string left unused are an
    # error under $DEBUG and a warning under $VERBOSE.
    def too_many
      Primitive.attr! :hidden
      return unless @posarg >= 0 && @nextarg <= @args.size
      return if @args.size == 1 && Hash === @args[0]

      raise ArgumentError, +"too many arguments for format string" if $DEBUG

      Warning.warn("#{Primitive.zr_warn_position}warning: too many arguments for format string\n") if $VERBOSE
    end

    def convert(b, value, flags, width, precision)
      Primitive.attr! :hidden
      case b
      when 100, 105, 117 then integer(value, 10, flags, width, precision, false)
      when 120 then integer(value, 16, flags, width, precision, false)
      when 88 then integer(value, 16, flags, width, precision, true)
      when 111 then integer(value, 8, flags, width, precision, false)
      when 98, 66 then integer(value, 2, flags, width, precision, b == 66)
      when 115 then pad(precision ? value.to_s[0, precision] : value.to_s, flags, width)
      when 112 then pad(precision ? value.inspect[0, precision] : value.inspect, flags, width)
      when 99 then character(value, flags, width)
      when 102 then float(value, flags, width, precision, :f, false)
      when 101, 69 then float(value, flags, width, precision, :e, b == 69)
      when 103, 71 then float(value, flags, width, precision, :g, b == 71)
      when 97, 65 then float(value, flags, width, precision, :a, b == 65)
      else raise ArgumentError, "malformed format string - %#{Primitive.zr_str_from_byte(b)}"
      end
    end

    # `%c`: a String gives its first character; a number is a character
    # of the result's encoding. US-ASCII past 127 turns the result binary,
    # as rb_ascii8bit_appendable_encoding_index does.
    def character(value, flags, width)
      Primitive.attr! :hidden
      if (text = String.try_convert(value))
        return pad(text[0] || +"", flags, width)
      end

      n = num2int(value)
      raise ArgumentError, +"invalid character" if n < 0

      enc = @out.encoding
      if enc.equal?(Encoding::US_ASCII) && n > 127 && n < 256
        @out.force_encoding(Encoding::BINARY)
        enc = Encoding::BINARY
      end
      char = if enc.equal?(Encoding::UTF_8)
               raise ArgumentError, +"invalid character" if n > 0x10FFFF

               # A surrogate is written as its three bytes, as mbcput does.
               n >= 0xD800 && n <= 0xDFFF ? [0xED, 0xA0 | ((n >> 6) & 0x1F), 0x80 | (n & 0x3F)].pack("C*").force_encoding(enc) : n.chr(enc)
             elsif Regexp.encoder(enc).max_len > 1
               # rb_enc_codelen: a code that makes no character of a
               # multibyte encoding has no length.
               char = begin
                 n.chr(enc)
               rescue RangeError
                 nil
               end
               raise ArgumentError, +"invalid character" unless char&.valid_encoding?

               char
             else
               n.chr(enc)
             end
      pad(char, flags, width)
    end

    # The digits with sign, prefix, precision and width applied; a
    # negative number in a base other than 10 without a sign flag
    # prints as CRuby's `..f01` two's complement.
    def integer(value, base, flags, width, precision, upper)
      Primitive.attr! :hidden
      n = Integer(value)
      signed = base == 10 || flags.include?("+") || flags.include?(" ")
      if n < 0 && !signed
        digits = complement(-n, base)
        fill = (base - 1).to_s(base)
        digits = fill * (precision - 2 - digits.bytesize) + digits if precision && digits.bytesize < precision - 2
        body = ".." + digits
        prefix = base_prefix(base, flags, n)
        if flags.include?("0") && !flags.include?("-") && width && prefix.bytesize + body.bytesize < width && precision.nil?
          digits = fill * (width - prefix.bytesize - 2 - digits.bytesize) + digits
          body = ".." + digits
        end
        result = prefix + body
        result = result.upcase if upper
        return pad(result, flags.delete("0"), width)
      end
      digits = n.abs.to_s(base)
      digits = +"" if precision == 0 && n == 0
      digits = "0" * (precision - digits.bytesize) + digits if precision && digits.bytesize < precision
      digits = "0" + digits if base == 8 && flags.include?("#") && !digits.start_with?("0")
      sign = if n < 0 then "-"
             elsif flags.include?("+") then "+"
             elsif flags.include?(" ") then " "
             else ""
             end
      prefix = base_prefix(base, flags, n)
      if flags.include?("0") && !flags.include?("-") && precision.nil? && width
        room = width - sign.bytesize - prefix.bytesize
        digits = "0" * (room - digits.bytesize) + digits if digits.bytesize < room
      end
      result = sign + prefix + digits
      result = result.upcase if upper
      pad(result, flags, width)
    end

    # `#` writes the base's own prefix. Octal's prefix is a leading
    # zero that the digits contain themselves, so it is not one of these.
    def base_prefix(base, flags, n)
      Primitive.attr! :hidden
      return +"" unless flags.include?("#") && n != 0

      { 16 => "0x", 2 => "0b" }.fetch(base, +"")
    end

    def complement(m, base)
      Primitive.attr! :hidden
      k = 1
      k += 1 until base**k >= m
      digits = (base**(k + 1) - m).to_s(base)
      top = (base - 1).to_s(base)
      digits = digits[1..] while digits.bytesize > 1 && digits.start_with?(top + top)
      digits
    end

    def pad(text, flags, width)
      Primitive.attr! :hidden
      return text if width.nil? || text.size >= width

      flags.include?("-") ? text.ljust(width) : text.rjust(width)
    end

    # %f of an Integer or a Rational, as CRuby's sprintf writes it: the
    # exact digits, the magnitude rounded half up at `precision` places,
    # its own fill, and no `#`.
    def exact_fixed(value, flags, width, precision)
      Primitive.attr! :hidden
      num, den = value.is_a?(Rational) ? [value.numerator, value.denominator] : [value, 1]
      sign = flags.include?("+") ? 1 : 0
      if num.negative?
        num = -num
        sign = -1
      end
      zero = 0
      if den == 1
        zero = precision
      else
        num = (num * 10**precision + den / 2) / den
      end
      digits = num.to_s
      len = digits.size + zero
      size = precision >= len ? precision + 1 : len
      size += 1 if sign != 0 || flags.include?(" ")
      size += 1 if precision > 0
      fill = width && width > size ? width - size : 0
      left = flags.include?("-")
      zeros = flags.include?("0") && !left
      out = +""
      out << " " * fill if fill > 0 && !left && !zeros
      if sign != 0
        out << (sign > 0 ? "+" : "-")
      elsif flags.include?(" ")
        out << " "
      end
      out << "0" * fill if fill > 0 && zeros
      out << (len > precision ? digits[0, len - precision] : "0")
      out << "." if precision > 0
      if zero > 0
        out << "0" * zero
      elsif precision > len
        out << "0" * (precision - len) << digits
      elsif precision > 0
        out << digits[len - precision, precision]
      end
      out << " " * fill if fill > 0 && left
      out
    end

    # %f, %e and %g round the shortest round-trip digits half to even,
    # as CRuby's dtoa comes out; past those digits, and when the
    # rounding place comes before the first digit, the exact value
    # decides.
    def float(value, flags, width, precision, style, upper)
      Primitive.attr! :hidden
      return exact_fixed(value, flags, width, precision || 6) if style == :f && (value.is_a?(Integer) || value.is_a?(Rational))

      x = Float(value)
      negative = x.negative? || (x.zero? && (1.0 / x).negative?)
      sign = negative ? "-" : (flags.include?("+") ? "+" : (flags.include?(" ") ? " " : ""))
      if x.nan? || x.infinite?
        text = x.nan? ? +"NaN" : +"Inf"
        text = +"+NaN" if x.nan? && flags.include?("+")
        text = +" NaN" if x.nan? && flags.include?(" ") && !flags.include?("+")
        text = sign + text unless x.nan?
        return pad(text, flags.delete("0"), width)
      end
      x = x.abs
      prefix = style == :a ? (upper ? +"0X" : +"0x") : +""
      body = case style
             when :f then fixed_text(x, precision || 6, flags)
             when :e then exponent_text(x, precision || 6, flags, upper)
             when :a then hex_text(x, precision, flags, upper)
             else general_text(x, precision, flags, upper)
             end
      if flags.include?("0") && !flags.include?("-") && width && sign.size + prefix.size + body.size < width
        body = "0" * (width - sign.size - prefix.size - body.size) + body
      end
      pad(sign + prefix + body, flags, width)
    end

    # `%a` without its `0x`: the exact value in hexadecimal, one digit
    # before the point. A subnormal is normalized first, so that digit
    # is 1 for every number but zero.
    def hex_text(x, precision, flags, upper)
      Primitive.attr! :hidden
      low, high = Primitive.zr_float_halves(x)
      bits = (high << 32) | low
      biased = (bits >> 52) & 0x7ff
      fraction = bits & 0xf_ffff_ffff_ffff
      lead = biased == 0 && fraction == 0 ? 0 : 1
      power = biased - 1023
      if biased == 0
        shift = 53 - fraction.bit_length
        fraction = (fraction << shift) & 0xf_ffff_ffff_ffff
        power = lead.zero? ? 0 : -1022 - shift
      end
      digits = fraction.to_s(16).rjust(13, "0")
      if precision.nil?
        digits = digits.sub(/0+\z/, "")
      else
        lead, digits, power = round_hex(lead, digits, precision, power)
      end
      point = digits.empty? ? (flags.include?("#") ? +"." : +"") : ".#{digits}"
      text = "#{lead}#{point}p#{power.negative? ? '-' : '+'}#{power.abs}"
      upper ? text.upcase : text
    end

    # The hexadecimal digits kept to `precision`, rounded half to even.
    # A carry past the leading digit halves it and lifts the exponent.
    def round_hex(lead, digits, precision, power)
      Primitive.attr! :hidden
      return [lead, digits.ljust(precision, "0"), power] if precision >= digits.size

      rest = digits[precision..]
      n = (lead.to_s(16) + digits[0, precision]).to_i(16)
      up = rest[0].to_i(16)
      n += 1 if up > 8 || (up == 8 && (rest[1..].delete("0") != +"" || n.odd?))
      text = n.to_s(16).rjust(precision + 1, "0")
      return [1, "0" * precision, power + 1] if text[0] == +"2"

      [text[0].to_i(16), text[1..], power]
    end

    def fixed_text(x, precision, flags)
      Primitive.attr! :hidden
      return zero_text(precision, flags) if x.zero?

      digits, point = Primitive.zr_float_shortest(x)
      k = point + precision
      if k <= 0
        exact, _ = exact_digits(x, 800)
        exact = exact[0, exact.size - 1] while exact.end_with?("0")
        return zero_text(precision, flags) unless k == 0 && exact > "5"

        digits = +"1"
        point = 1 - precision
      else
        digits, point = rounded_digits(x, digits, point, k)
      end
      whole = point <= 0 ? +"0" : (digits[0, point] + ("0" * (point > digits.size ? point - digits.size : 0)))
      fraction = point >= 0 ? digits[point..].to_s : "0" * -point + digits
      fraction = fraction[0, precision] + ("0" * (precision > fraction.size ? precision - fraction.size : 0))
      precision == 0 && !flags.include?("#") ? whole : "#{whole}.#{fraction}"
    end

    # The first k digits of x: the shortest digits rounded half to
    # even when they are longer, else the exact digits.
    def rounded_digits(x, digits, point, k)
      Primitive.attr! :hidden
      return exact_digits(x, k) if digits.size < k
      return [digits, point] if digits.size == k

      kept = digits[0, k]
      rest = digits[k..]
      n = kept.to_i
      n += 1 if rest[0] > "5" || (rest[0] == +"5" && (rest[1..].delete("0") != +"" || n.odd?))
      digits = n.to_s
      if digits.size > k
        digits = digits[0, k]
        point += 1
      end
      [digits, point]
    end

    # The first k significant digits of x's exact decimal value, rounded
    # half to even, and where the point falls after them, as ecvt(3)
    # gives them: x is its mantissa times a power of two, so the digits
    # are one Integer division.
    def exact_digits(x, k)
      Primitive.attr! :hidden
      low, high = Primitive.zr_float_halves(x)
      bits = (high << 32) | low
      biased = (bits >> 52) & 0x7ff
      mantissa = bits & 0xf_ffff_ffff_ffff
      return ["0" * k, 1] if biased == 0 && mantissa == 0

      if biased == 0
        biased = 1
      else
        mantissa |= 1 << 52
      end
      shift = biased - 1075
      num, den = shift >= 0 ? [mantissa << shift, 1] : [mantissa, 1 << -shift]
      # 10**(point - 1) <= num / den < 10**point
      point = num.to_s.size - den.to_s.size
      point += 1 while num >= den * 10**point
      point -= 1 while num * 10 < den * 10**point
      scale = k - point
      num *= 10**scale if scale.positive?
      den *= 10**-scale if scale.negative?
      q, r = num.divmod(den)
      q += 1 if 2 * r > den || (2 * r == den && q.odd?)
      return [q.to_s, point] unless q == 10**k

      [(q / 10).to_s, point + 1]
    end

    def zero_text(precision, flags)
      Primitive.attr! :hidden
      precision == 0 && !flags.include?("#") ? +"0" : "0." + "0" * precision
    end

    def exponent_text(x, precision, flags, upper)
      Primitive.attr! :hidden
      if x.zero?
        digits = "0" * (precision + 1)
        exponent = 0
      else
        digits, point = Primitive.zr_float_shortest(x)
        digits, point = rounded_digits(x, digits, point, precision + 1)
        digits += "0" * (precision + 1 - digits.size)
        exponent = point - 1
      end
      mantissa = precision == 0 && !flags.include?("#") ? digits[0] : "#{digits[0]}.#{digits[1..]}"
      "#{mantissa}#{upper ? 'E' : 'e'}#{exponent < 0 ? '-' : '+'}#{format('%02d', exponent.abs)}"
    end

    def general_text(x, precision, flags, upper)
      Primitive.attr! :hidden
      precision = 6 if precision.nil?
      precision = 1 if precision == 0
      exponent = x.zero? ? 0 : rounded_digits(x, *Primitive.zr_float_shortest(x), precision)[1] - 1
      text = if exponent < -4 || exponent >= precision
               exponent_text(x, precision - 1, flags, upper)
             else
               fixed_text(x, precision - 1 - exponent, flags)
             end
      return text if flags.include?("#")

      trim_zeros(text)
    end

    # Trailing zeros of a fraction go, and the point after them.
    def trim_zeros(text)
      Primitive.attr! :hidden
      e = text.index("e") || text.index("E")
      mantissa = e ? text[0, e] : text
      tail = e ? text[e..] : +""
      return text unless mantissa.include?(".")

      mantissa = mantissa[0, mantissa.size - 1] while mantissa.end_with?("0")
      mantissa = mantissa[0, mantissa.size - 1] if mantissa.end_with?(".")
      mantissa + tail
    end
  end

  private_constant :Formatter
end

class String
  # rb_str_format_m: an Array, or an object with to_ary, gives the
  # arguments; anything else is the one argument.
  def %(args)
    list = Array.try_convert(args)
    Kernel.formatted([self, *(list || [args])])
  end
end
