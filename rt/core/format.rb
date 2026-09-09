# `Kernel#format` over Integer, String, Symbol and the `%c` and `%p`
# directives; a Float directive stops by name until Float lands.
module Kernel
  def format(spec, *args)
    Formatter.new(spec, args).render
  end
  alias sprintf format

  def printf(*args)
    return nil if args.empty?

    print(format(*args))
    nil
  end

  private :format, :sprintf, :printf

  # One `format` call: walks the spec's bytes, taking arguments in
  # order, by position (`%1$d`) or by name (`%<n>d`, `%{n}`). Its
  # methods are hidden helpers: a backtrace shows Kernel#format alone.
  class Formatter
    def initialize(spec, args)
      Primitive.attr! :hidden
      @spec = spec
      @args = args
      @next = 0
      @numbered = false
      @out = +""
    end

    def render
      Primitive.attr! :hidden
      i = 0
      while i < @spec.bytesize
        b = @spec.getbyte(i)
        if b != 37
          @out << Primitive.zr_str_from_byte(b)
          i += 1
          next
        end
        i = directive(i + 1)
      end
      @out
    end

    private

    def directive(i)
      Primitive.attr! :hidden
      flags = +""
      width = nil
      precision = nil
      value = nil
      have_value = false
      while true
        raise ArgumentError, "incomplete format specifier; use %% (double %) instead" if i >= @spec.bytesize

        b = @spec.getbyte(i)
        case b
        when 45, 43, 32, 48, 35 then flags << Primitive.zr_str_from_byte(b)
        when 42
          width = Integer(take_next)
          if width < 0
            flags << "-"
            width = -width
          end
        when 46
          i += 1
          if @spec.getbyte(i) == 42
            precision = Integer(take_next)
            precision = nil if precision < 0
          else
            precision, i = number(i)
            precision ||= 0
            i -= 1
          end
        when 49..57
          n, i = number(i)
          if @spec.getbyte(i) == 36
            value = positional(n)
            have_value = true
          else
            width = n
            i -= 1
          end
        when 60
          stop = @spec.index(">", i)
          raise ArgumentError, "malformed name - unmatched parenthesis" unless stop

          value = named(@spec[i + 1...stop], "<", ">")
          have_value = true
          i = stop
        when 123
          stop = @spec.index("}", i)
          raise ArgumentError, "malformed name - unmatched parenthesis" unless stop

          @out << named(@spec[i + 1...stop], "{", "}").to_s
          return stop + 1
        when 37
          raise ArgumentError, "invalid format character - %" unless flags.empty? && width.nil?

          @out << "%"
          return i + 1
        else
          value = take_next unless have_value
          @out << convert(b, value, flags, width, precision)
          return i + 1
        end
        i += 1
      end
    end

    def number(i)
      Primitive.attr! :hidden
      n = 0
      while i < @spec.bytesize && @spec.getbyte(i).between?(48, 57)
        n = n * 10 + (@spec.getbyte(i) - 48)
        i += 1
      end
      [n, i]
    end

    # An argument taken in order. A template names its arguments one
    # way or the other, never both.
    def take_next
      Primitive.attr! :hidden
      raise ArgumentError, "unnumbered(#{@next + 1}) mixed with numbered" if @numbered
      raise ArgumentError, "too few arguments" if @next >= @args.size

      v = @args[@next]
      @next += 1
      v
    end

    def positional(n)
      Primitive.attr! :hidden
      raise ArgumentError, "numbered(#{n}) after unnumbered(#{@next})" if @next.positive?
      raise ArgumentError, "invalid index - #{n}$" if n < 1 || n > @args.size

      @numbered = true
      @args[n - 1]
    end

    # The message names the key inside the brackets the program wrote.
    def named(name, open, close)
      Primitive.attr! :hidden
      raise ArgumentError, "named#{open}#{name}#{close} after unnumbered(#{@next})" if @next.positive?
      raise ArgumentError, "one hash required" unless @args.size == 1 && @args[0].is_a?(Hash)

      hash = @args[0]
      key = name.to_sym
      raise KeyError.new("key#{open}#{name}#{close} not found", receiver: hash, key: key) unless hash.key?(key)

      hash[key]
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

    def character(value, flags, width)
      Primitive.attr! :hidden
      if value.is_a?(String)
        raise ArgumentError, "%c requires a character" if value.empty?

        pad(value[0], flags, width)
      else
        n = Integer(value)
        raise ArgumentError, "invalid character" if n < 0

        pad(n.chr, flags, width)
      end
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
      digits = "" if precision == 0 && n == 0
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
    # zero the digits carry themselves, so it is not one of these.
    def base_prefix(base, flags, n)
      Primitive.attr! :hidden
      return "" unless flags.include?("#") && n != 0

      { 16 => "0x", 2 => "0b" }.fetch(base, "")
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

    # %f, %e and %g round the shortest round-trip digits half to even,
    # as CRuby's dtoa comes out; past those digits, and when the
    # rounding place comes before the first digit, the exact value
    # decides.
    def float(value, flags, width, precision, style, upper)
      Primitive.attr! :hidden
      x = Float(value)
      negative = x.negative? || (x.zero? && (1.0 / x).negative?)
      sign = negative ? "-" : (flags.include?("+") ? "+" : (flags.include?(" ") ? " " : ""))
      if x.nan? || x.infinite?
        text = x.nan? ? "NaN" : "Inf"
        text = "+NaN" if x.nan? && flags.include?("+")
        text = " NaN" if x.nan? && flags.include?(" ") && !flags.include?("+")
        text = sign + text unless x.nan?
        return pad(text, flags.delete("0"), width)
      end
      x = x.abs
      prefix = style == :a ? (upper ? "0X" : "0x") : ""
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
      point = digits.empty? ? (flags.include?("#") ? "." : "") : ".#{digits}"
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
      n += 1 if up > 8 || (up == 8 && (rest[1..].delete("0") != "" || n.odd?))
      text = n.to_s(16).rjust(precision + 1, "0")
      return [1, "0" * precision, power + 1] if text[0] == "2"

      [text[0].to_i(16), text[1..], power]
    end

    def fixed_text(x, precision, flags)
      Primitive.attr! :hidden
      return zero_text(precision, flags) if x.zero?

      digits, point = Primitive.zr_float_shortest(x)
      k = point + precision
      if k <= 0
        exact, _, _ = Primitive.zr_float_digits(x, 800, false)
        exact = exact[0, exact.size - 1] while exact.end_with?("0")
        return zero_text(precision, flags) unless k == 0 && exact > "5"

        digits = "1"
        point = 1 - precision
      else
        digits, point = rounded_digits(x, digits, point, k)
      end
      whole = point <= 0 ? "0" : (digits[0, point] + "0" * [point - digits.size, 0].max)
      fraction = point >= 0 ? digits[point..].to_s : "0" * -point + digits
      fraction = fraction[0, precision] + "0" * [precision - fraction.size, 0].max
      precision == 0 && !flags.include?("#") ? whole : "#{whole}.#{fraction}"
    end

    # The first k digits of x: the shortest digits rounded half to
    # even when they are longer, else the exact digits.
    def rounded_digits(x, digits, point, k)
      Primitive.attr! :hidden
      return Primitive.zr_float_digits(x, k, false).first(2) if digits.size < k
      return [digits, point] if digits.size == k

      kept = digits[0, k]
      rest = digits[k..]
      n = kept.to_i
      n += 1 if rest[0] > "5" || (rest[0] == "5" && (rest[1..].delete("0") != "" || n.odd?))
      digits = n.to_s
      if digits.size > k
        digits = digits[0, k]
        point += 1
      end
      [digits, point]
    end

    def zero_text(precision, flags)
      Primitive.attr! :hidden
      precision == 0 && !flags.include?("#") ? "0" : "0." + "0" * precision
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
      tail = e ? text[e..] : ""
      return text unless mantissa.include?(".")

      mantissa = mantissa[0, mantissa.size - 1] while mantissa.end_with?("0")
      mantissa = mantissa[0, mantissa.size - 1] if mantissa.end_with?(".")
      mantissa + tail
    end
  end

  private_constant :Formatter
end

class String
  def %(args)
    format(self, *(args.is_a?(Array) ? args : [args]))
  end
end
