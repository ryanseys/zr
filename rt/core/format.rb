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

          value = named(@spec[i + 1...stop])
          have_value = true
          i = stop
        when 123
          stop = @spec.index("}", i)
          raise ArgumentError, "malformed name - unmatched parenthesis" unless stop

          @out << named(@spec[i + 1...stop]).to_s
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

    def take_next
      Primitive.attr! :hidden
      raise ArgumentError, "too few arguments" if @next >= @args.size

      v = @args[@next]
      @next += 1
      v
    end

    def positional(n)
      Primitive.attr! :hidden
      raise ArgumentError, "invalid index - #{n}$" if n < 1 || n > @args.size

      @args[n - 1]
    end

    def named(name)
      Primitive.attr! :hidden
      raise ArgumentError, "one hash required" unless @args.size == 1 && @args[0].is_a?(Hash)

      hash = @args[0]
      key = name.to_sym
      raise KeyError.new("key<#{name}> not found", receiver: hash, key: key) unless hash.key?(key)

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
      when 102, 101, 69, 103, 71, 97, 65 then Primitive.zr_unimplemented("Kernel#format with a Float directive")
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
        digits = fill * (precision - digits.bytesize) + digits if precision && digits.bytesize < precision
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

    def base_prefix(base, flags, n)
      Primitive.attr! :hidden
      return "" unless flags.include?("#") && n != 0

      { 16 => "0x", 8 => "0", 2 => "0b" }.fetch(base, "")
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
      return text if width.nil? || text.bytesize >= width

      flags.include?("-") ? text.ljust(width) : text.rjust(width)
    end
  end

  private_constant :Formatter
end

class String
  def %(args)
    format(self, *(args.is_a?(Array) ? args : [args]))
  end
end
