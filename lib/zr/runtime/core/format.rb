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
  # `watched` is the Array that String#% takes its arguments from.
  def self.formatted(args, watched = nil)
    Primitive.attr! :hidden
    raise ArgumentError, +"too few arguments" if args.empty?

    Formatter.new(Primitive.zr_str_operand(args.first), args.drop(1), watched).render
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

    def initialize(spec, args, watched = nil)
      Primitive.attr! :hidden
      encoding = Encoding.at(Primitive.zr_str_encoding_index_m(spec))
      raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{encoding}" unless encoding.ascii_compatible?

      # A subclass's text is read as its bytes, as rb_str_format reads it.
      @spec = Primitive.zr_real_class(spec).equal?(String) ? spec : String.new(spec)
      @args = args
      # format_args_check: String#%'s Array, which a conversion must not
      # change while the format reads it.
      @watched = watched
      @watched_size = watched&.size
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
      args_check
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

      args_check
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

      args_check
      @posarg = -1
      nth(n)
    end

    def args_check
      Primitive.attr! :hidden
      raise RuntimeError, +"array modified during formatting" if @watched && Primitive.zr_ary_len_m(@watched) != @watched_size
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

    # sprint_exit: arguments in order that the string left unused are a
    # warning under $VERBOSE; ruby 4.1 no longer raises under $DEBUG.
    def too_many
      Primitive.attr! :hidden
      return unless @posarg >= 0 && @nextarg <= @args.size
      return if @args.size == 1 && Hash === @args[0]

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
               # rb_enc_codelen gives no length past a byte, and
               # rb_ascii8bit_appendable_encoding_index refuses that code
               # of a binary or US-ASCII result first.
               raise RangeError, "#{n} out of char range" if n > 255 && (enc.equal?(Encoding::BINARY) || enc.equal?(Encoding::US_ASCII))
               raise ArgumentError, +"invalid character" if n > 255

               n.chr(enc)
             end
      # CHECK_WIDTH: the character and its padding fit an int.
      raise ArgumentError, +"width too big" if width && width > 1 && char.bytesize > 2_147_483_647 - (width - 1)

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

    # %f, %e and %g of a Float take their digits from dtoa and lay them
    # out as BSD_vfprintf does (bsd_float_text); %a writes the bits.
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
      body = if style == :a
               hex_text(x, precision, flags, upper)
             else
               conversion = style == :f ? "f" : (style == :e ? "e" : "g")
               bsd_float_text(x, upper ? conversion.upcase : conversion, precision, flags.include?("#"))
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

    # The powers of ten that dtoa keeps as doubles (tens and bigtens).
    TENS = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
            1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22].freeze
    BIGTENS = [1e16, 1e32, 1e64, 1e128, 1e256].freeze
    # The most digits that the double arithmetic of dtoa tries
    # (Quick_max), and the largest power of ten in a double integer
    # (Int_max).
    QUICK_MAX = 14
    INT_MAX = 14
    # BSD_vfprintf's MAXFRACT: the most digits it asks dtoa for.
    MAX_FRACT = 1026
    # 2**52, which scales a double by its precision (P - 1 bits).
    PRECISION = 4_503_599_627_370_496.0

    # BSD_vfprintf's %e, %f and %g of a finite, positive `x`, without the
    # sign and the field width: `ch` is the conversion, `prec` the given
    # precision or nil, `alt` the `#` flag.
    def bsd_float_text(x, ch, prec, alt)
      Primitive.attr! :hidden
      fixed = ch == "f"
      fprec = 0
      if ch == "e" || ch == "E"
        alt ||= prec != 0
        prec.nil? ? prec = 7 : fprec = prec += 1
      else
        alt ||= fixed && prec != 0
        prec.nil? ? prec = 6 : fprec = prec
      end
      # cvt: the digits, and with `#` the zeros that dtoa left out.
      ndigits = prec < MAX_FRACT ? prec : MAX_FRACT
      digits, expt = dtoa(x, fixed ? 3 : 2, ndigits)
      if alt
        size = ndigits + (fixed ? expt : 0)
        digits << "0" * (size - digits.size) if digits.size < size
      end
      ndig = digits.size
      if ch == "g" || ch == "G"
        ch = expt <= -4 || (expt > prec && expt > 1) ? (ch == "g" ? "e" : "E") : "g"
      end
      return exponent_form(x, digits, expt - 1, ch, alt, fprec) if ch == "e" || ch == "E"

      if x.zero?
        return +"0" if ndig <= 1 && !alt

        return "0." + "0" * (ndig >= fprec ? ndig - 1 : fprec - (fixed ? 0 : 1))
      end
      pad = fprec - ndig + (fixed ? expt : 0)
      tail = alt && pad > 0 ? "0" * pad : +""
      if expt == 0 && ndig == 0 && !alt
        +"0"
      elsif expt <= 0
        "0." + "0" * -expt + digits + tail
      elsif expt >= ndig
        digits + "0" * (expt - ndig) + (alt ? "." : "")
      else
        "#{digits[0, expt]}.#{digits[expt..]}#{tail}"
      end
    end

    # The `e` form: one digit, the point and the others, then the
    # exponent in at least two digits.
    def exponent_form(x, digits, exponent, ch, alt, fprec)
      Primitive.attr! :hidden
      ndig = digits.size
      out = +digits[0]
      if ndig > 1 || alt
        out << "." << (x.zero? ? "0" * (ndig - 1) : digits[1..])
        out << "0" * (fprec - ndig) if alt && fprec > ndig
      end
      out << ch << (exponent < 0 ? "-" : "+") << (exponent.abs < 10 ? "0" : "") << exponent.abs.to_s
    end

    # BSD__dtoa of CRuby's missing/dtoa.c, in mode 2 (`ndigits`
    # significant digits) and mode 3 (`ndigits` past the point): the
    # digits of a finite, positive `x` and where the point falls after
    # them (decpt). Trailing zeros mostly go. It first tries double
    # arithmetic, whose remainder within its error bound of one half is a
    # tie that goes to an even digit, and that tie also biases the exact
    # count when the doubles cannot settle the digits.
    def dtoa(x, mode, ndigits)
      Primitive.attr! :hidden
      return [+"0", 1] if x.zero?

      low, high = Primitive.zr_float_halves(x)
      biased = high >> 20
      fraction = ((high & 0xf_ffff) << 32) | low
      # d2b: x is b * 2**be, with b odd and bbits bits long.
      b = biased == 0 ? fraction : fraction | (1 << 52)
      be = (biased == 0 ? -1074 : biased - 1075)
      shift = (b & -b).bit_length - 1
      b >>= shift
      be += shift
      bbits = b.bit_length
      if biased == 0
        # A subnormal: its top 32 bits make the estimate.
        i = bbits + be + 1074
        top = i > 32 ? ((high << (64 - i)) | (low >> (i - 32))) : low << (32 - i)
        d2 = (top & 0xffff_ffff).to_f / 2_147_483_648.0
        i -= 1075
      else
        d2 = (fraction | (1 << 52)).to_f / PRECISION
        i = biased - 1023
      end
      # k = floor(log10(x)), estimated from above or exact.
      ds = (d2 - 1.5) * 0.289529654602168 + 0.1760912590558 + i * 0.301029995663981
      k = ds.to_i
      k -= 1 if ds < 0 && ds != k
      k_check = true
      if k >= 0 && k < TENS.size
        k -= 1 if x < TENS[k]
        k_check = false
      end
      if mode == 2
        ndigits = 1 if ndigits <= 0
        ilim = ilim1 = ndigits
      else
        ilim = ndigits + k + 1
        ilim1 = ilim - 1
      end
      half = false
      if ilim >= 0 && ilim <= QUICK_MAX
        quick = quick_digits(x, k, ilim, ilim1, ndigits, k_check)
        return quick if quick.is_a?(Array)

        half = quick == :half
      end
      return small_integer_digits(x, k, ilim, ndigits) if be >= 0 && k <= INT_MAX

      exact_digits(b, be, k, ilim, ilim1, mode, ndigits, k_check, half)
    end

    # dtoa's try_quick: the digits in double arithmetic, with a bound on
    # its error. Returns the digits and decpt, or :half for a remainder
    # that the bound leaves at one half after an even digit, or nil when
    # it cannot tell.
    def quick_digits(d, k, ilim, ilim1, ndigits, k_check)
      Primitive.attr! :hidden
      i = 0
      ieps = 2
      if k > 0
        ds = TENS[k & 0xf]
        j = k >> 4
        if j & 0x10 != 0
          j &= 0xf
          d /= BIGTENS[4]
          ieps += 1
        end
        while j != 0
          if j.odd?
            ieps += 1
            ds *= BIGTENS[i]
          end
          j >>= 1
          i += 1
        end
        d /= ds
      elsif k < 0
        d *= TENS[-k & 0xf]
        j = -k >> 4
        while j != 0
          if j.odd?
            ieps += 1
            d *= BIGTENS[i]
          end
          j >>= 1
          i += 1
        end
      end
      if k_check && d < 1.0 && ilim > 0
        return nil if ilim1 <= 0

        ilim = ilim1
        k -= 1
        d *= 10.0
        ieps += 1
      end
      eps = (ieps * d + 7.0) / PRECISION
      if ilim == 0
        d -= 5.0
        return [+"1", k + 2] if d > eps
        return [+"", -ndigits] if d < -eps

        return nil
      end
      eps *= TENS[ilim - 1]
      s = +""
      n = 1
      loop do
        digit = d.to_i
        d -= digit
        ilim = n if d.zero?
        s << (48 + digit)
        if n == ilim
          return bump_up(s, k) if d > 0.5 + eps
          return [trim_zeros(s), k + 1] if d < 0.5 - eps
          return bump_up(s, k) if s.getbyte(-1).odd?

          return :half
        end
        n += 1
        d *= 10.0
      end
    end

    # A positive integer below 10**15 in double arithmetic, which is
    # exact: its digits stop at a zero remainder, else at ilim with the
    # last one rounded half to even, and keep any zeros before that.
    def small_integer_digits(d, k, ilim, ndigits)
      Primitive.attr! :hidden
      ds = TENS[k]
      if ndigits < 0 && ilim <= 0
        return [+"", -ndigits] if ilim < 0 || d <= 5 * ds

        return [+"1", k + 2]
      end
      s = +""
      n = 1
      loop do
        digit = (d / ds).to_i
        d -= digit * ds
        s << (48 + digit)
        break if d.zero?

        if n == ilim
          d += d
          return bump_up(s, k) if d > ds || (d == ds && digit.odd?)

          break
        end
        n += 1
        d *= 10.0
      end
      [s, k + 1]
    end

    # The digits of b * 2**be over 10**k, by long division, the last
    # rounded half to even. After a tie that the quick count saw, an odd
    # last digit only goes up, and the nines before it go.
    def exact_digits(b, be, k, ilim, ilim1, mode, ndigits, k_check, half)
      Primitive.attr! :hidden
      num = be >= 0 ? b << be : b
      den = be >= 0 ? 1 : 1 << -be
      k >= 0 ? den *= 10**k : num *= 10**-k
      if k_check && num < den
        k -= 1
        num *= 10
        ilim = ilim1
      end
      if ilim <= 0 && mode == 3
        return [+"", -ndigits] if ilim < 0 || num <= den * 5

        return [+"1", k + 2]
      end
      s = +""
      n = 1
      digit = 0
      loop do
        digit, num = num.divmod(den)
        s << (48 + digit)
        return [s, k + 1] if num.zero?
        break if n >= ilim

        num *= 10
        n += 1
      end
      twice = num << 1
      return [trim_zeros(s), k + 1] unless twice > den || (twice == den && digit.odd?)

      s.chop! while s.end_with?("9")
      return [+"1", k + 2] if s.empty?

      s.setbyte(-1, s.getbyte(-1) + 1) if !half || s.getbyte(-1).odd?
      [s, k + 1]
    end

    def trim_zeros(s)
      Primitive.attr! :hidden
      s.chop! while s.end_with?("0")
      s
    end

    # bump_up: the last digit goes up, a nine carries, and all nines
    # become a 1 one place higher.
    def bump_up(s, k)
      Primitive.attr! :hidden
      s.chop! while s.end_with?("9")
      return [+"1", k + 2] if s.empty?

      s.setbyte(-1, s.getbyte(-1) + 1)
      [s, k + 1]
    end
  end

  private_constant :Formatter
end

class String
  # rb_str_format_m: an Array, or an object with to_ary, gives the
  # arguments; anything else is the one argument.
  def %(args)
    list = Array.try_convert(args)
    Kernel.formatted([self, *(list || [args])], list)
  end
end
