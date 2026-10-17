# frozen_string_literal: true

# Decimal numbers with as many digits as the caller requests.
#
# A value is `sign * digits * 10 ** (exponent - digit count)`, so the
# printed form `0.<digits>e<exponent>` reads directly from the fields.
# `digits` is an Integer with no trailing zero, so equality and the
# printed form are the same comparison.
class BigDecimal < Numeric
  include Comparable

  ROUND_UP = 1
  ROUND_DOWN = 2
  ROUND_HALF_UP = 3
  ROUND_HALF_DOWN = 4
  ROUND_CEILING = 5
  ROUND_FLOOR = 6
  ROUND_HALF_EVEN = 7

  ROUND_MODE = 256
  EXCEPTION_INFINITY = 1
  EXCEPTION_OVERFLOW = 1
  EXCEPTION_NaN = 2
  EXCEPTION_UNDERFLOW = 4
  EXCEPTION_ZERODIVIDE = 16
  EXCEPTION_ALL = 255
  SIGN_NaN = 0
  SIGN_POSITIVE_ZERO = 1
  SIGN_NEGATIVE_ZERO = -1
  SIGN_POSITIVE_FINITE = 2
  SIGN_NEGATIVE_FINITE = -2
  SIGN_POSITIVE_INFINITE = 3
  SIGN_NEGATIVE_INFINITE = -3
  VERSION = "4.1.3"

  # Ruby keeps its digits nine at a time, in base a thousand million.
  BASE = 1_000_000_000

  # A class with no allocator of its own, which every reader of the
  # object protocol checks.
  ALLOCATE = Class.instance_method(:allocate)
  private_constant :ALLOCATE

  # rb_undef_alloc_func: no allocate method, only the error.
  def self.allocate
    Primitive.attr! :hidden
    raise TypeError, "allocator undefined for BigDecimal"
  end

  # As many digits as a Float has, which is the number that a division
  # adds to the wider operand before it stops.
  DOUBLE_FIG = 16
  # The exponents a value keeps, in decimal digits: the C keeps one per
  # nine-digit word, in a signed word (VP_EXPONENT_MAX and _MIN, with C's
  # division, which truncates). Past them a value is infinite or zero.
  EXPONENT_MAX = ((2**63) - 1) / 9 * 9
  EXPONENT_MIN = (-(((2**63) - 8) / 9) * 9) - 8
  private_constant :DOUBLE_FIG, :EXPONENT_MAX, :EXPONENT_MIN

  # The three settings, each the current fiber's own, as the C keeps them
  # (rb_thread_local_aref), under the C's names.
  EXCEPTION_MODE_KEY = :"BigDecimal.exception_mode"
  ROUNDING_MODE_KEY = :"BigDecimal.rounding_mode"
  PRECISION_LIMIT_KEY = :"BigDecimal.precision_limit"
  # The bits of the exception word, in the order BigDecimal_mode sets them.
  EXCEPTION_BITS = [EXCEPTION_INFINITY, EXCEPTION_NaN, EXCEPTION_UNDERFLOW, EXCEPTION_ZERODIVIDE].freeze
  private_constant :EXCEPTION_MODE_KEY, :ROUNDING_MODE_KEY, :PRECISION_LIMIT_KEY, :EXCEPTION_BITS

  class << self
    # BigDecimal_mode: a selector with an exception bit reads or sets
    # those bits; ROUND_MODE reads or sets the rounding.
    def mode(selector, value = nil)
      flags = Integer.send(:int_operand, selector)
      if flags.anybits?(EXCEPTION_ALL)
        word = exception_mode
        return word if value.nil?
        raise ArgumentError, +"second argument must be true or false" unless value == true || value == false

        EXCEPTION_BITS.each { |bit| word = value ? word | bit : word & ~bit if flags.anybits?(bit) }
        return Thread.current[EXCEPTION_MODE_KEY] = word
      end
      if flags == ROUND_MODE
        return rounding_mode if value.nil?

        return Thread.current[ROUNDING_MODE_KEY] = rounding(value)
      end
      raise TypeError, +"first argument for BigDecimal.mode invalid"
    end

    # BigDecimal_limit: the old limit, so a caller can restore it.
    def limit(digits = nil)
      was = precision_limit
      unless digits.nil?
        digits = Integer.send(:int_operand, digits)
        raise ArgumentError, +"argument must be positive" if digits.negative?

        Thread.current[PRECISION_LIMIT_KEY] = digits
      end
      was
    end

    def double_fig = DOUBLE_FIG

    def save_rounding_mode
      was = rounding_mode
      yield
    ensure
      Thread.current[ROUNDING_MODE_KEY] = was
    end

    def save_limit
      was = precision_limit
      yield
    ensure
      Thread.current[PRECISION_LIMIT_KEY] = was
    end

    def save_exception_mode
      was = exception_mode
      yield
    ensure
      Thread.current[EXCEPTION_MODE_KEY] = was
    end

    # VpGetException, VpGetRoundMode and VpGetPrecLimit: a fiber that has
    # none yet gets the default, which the C writes there.
    def exception_mode
      Primitive.attr! :hidden
      Thread.current[EXCEPTION_MODE_KEY] ||= 0
    end

    def rounding_mode
      Primitive.attr! :hidden
      Thread.current[ROUNDING_MODE_KEY] ||= ROUND_HALF_UP
    end

    def precision_limit
      Primitive.attr! :hidden
      Thread.current[PRECISION_LIMIT_KEY] ||= 0
    end

    # The results that ruby refuses to return when the matching bit is
    # set in the mode word.
    # A NaN that an operation makes "results to" NaN; one that an operand
    # brings in "results in" it, as VpException words the two.
    def nan_result(given = false)
      Primitive.attr! :hidden
      unless exception_mode.nobits?(EXCEPTION_NaN)
        raise FloatDomainError, given ? refused(NAN) : +"Computation results to 'NaN'"
      end

      NAN
    end

    def infinity_result(sign, word = "to")
      Primitive.attr! :hidden
      unless exception_mode.nobits?(EXCEPTION_INFINITY)
        raise FloatDomainError, "Computation results #{word} '#{sign.negative? ? '-' : ''}Infinity'"
      end

      sign.negative? ? -INFINITY : INFINITY
    end

    def zero_divide_result(sign)
      Primitive.attr! :hidden
      raise FloatDomainError, +"Divide by zero" unless exception_mode.nobits?(EXCEPTION_ZERODIVIDE)

      infinity_result(sign, "in")
    end

    # How an error names a value: a special constant by its inspect, any
    # other object by its class, as rb_special_const_p decides.
    def named(value)
      Primitive.attr! :hidden
      value.nil? || value == true || value == false || value.is_a?(Symbol) ? value.inspect : value.class
    end

    # What a value that is not finite says where ruby refuses it: at a
    # parse, or where it must become an Integer.
    def refused(value)
      Primitive.attr! :hidden
      return "Computation results in 'NaN' (Not a Number)" if value.nan?

      "Computation results in '#{value.infinite?.negative? ? '-' : ''}Infinity'"
    end

    # check_rounding_mode: a Symbol names a rounding, anything else is its
    # number.
    ROUNDINGS = { up: ROUND_UP, down: ROUND_DOWN, truncate: ROUND_DOWN, half_up: ROUND_HALF_UP,
                  default: ROUND_HALF_UP, half_down: ROUND_HALF_DOWN, half_even: ROUND_HALF_EVEN,
                  banker: ROUND_HALF_EVEN, ceiling: ROUND_CEILING, ceil: ROUND_CEILING,
                  floor: ROUND_FLOOR }.freeze

    def rounding(value)
      Primitive.attr! :hidden
      if value.is_a?(Symbol)
        return ROUNDINGS.fetch(value) { raise ArgumentError, "invalid rounding mode (#{value})" }
      end

      number = Integer.send(:int_operand, value)
      raise ArgumentError, "invalid rounding mode (#{value.inspect})" unless (ROUND_UP..ROUND_HALF_EVEN).cover?(number)

      number
    end

    # The one way an instance is built: nothing else writes the fields.
    def build(sign, digits, exponent, special = nil)
      Primitive.attr! :hidden
      value = ALLOCATE.bind_call(self)
      value.send(:setup, sign, digits, exponent, special)
      value
    end

    # The text ends at a NUL, as String#to_f reads it.
    def interpret_loosely(source)
      text = String.try_convert(source) or raise TypeError, no_implicit_conversion(source, "String")
      text.send(:ascii_compatible!)
      read(text.split("\0", 2).first.to_s, false)
    end

    # rb_str_convert_to_BigDecimal: the text in an ASCII-compatible
    # encoding, with no NUL (StringValueCStr), else nil when exceptions are
    # off.
    def c_text(text, exception)
      Primitive.attr! :hidden
      text.send(:ascii_compatible!)
      return text unless text.include?("\0")
      return nil unless exception

      raise ArgumentError, "string contains null byte"
    end

    # Reading a decimal out of text. `strict` refuses anything left
    # over, which is what `BigDecimal("1x")` does; loose reading keeps
    # as much as it understood.
    def read(source, strict, exception = true)
      Primitive.attr! :hidden
      # An underscore stands between two digits, or after the last one.
      text = source.gsub(/(?<=\d)_(?=\d|\s*\z)/, "")
      if (special = text[/\A\s*(NaN|[-+]?Infinity)\s*\z/, 1])
        # A new value, as the C makes for text; the shared ones come from Floats.
        return checked(special == "NaN" ? build(1, 0, 0, :nan) : build(special.start_with?("-") ? -1 : 1, 0, 0, :infinity))
      end

      match = /\A\s*([-+]?)(\d*)(?:\.(\d*))?(?:[eEdD]([-+]?\d+))?/.match(text)
      whole = match[2].to_s
      fraction = match[3].to_s
      empty = whole.empty? && fraction.empty?
      if strict && (empty || !text[match.end(0)..].to_s.strip.empty?)
        return nil unless exception

        raise ArgumentError, "invalid value for BigDecimal(): #{source.inspect}"
      end
      return build(1, 0, 0) if empty

      sign = match[1] == "-" ? -1 : 1
      digits = "#{whole}#{fraction}"
      # VpCtoV checks the exponent of the integer part's first digit, up to
      # a whole word: past the range, a nonzero value with a positive
      # exponent is infinite, and any other is zero.
      written = match[4].to_i + whole.sub(/\A0+/, "").length
      word = -(-written).div(9) * 9
      return read_overflow(sign, digits.match?(/[1-9]/) && word.positive?) unless word.between?(EXPONENT_MIN, EXPONENT_MAX)
    
      lead = digits.length - digits.sub(/\A0+/, "").length
      from_int(sign, digits.to_i, whole.length + match[4].to_i - lead)
    end
    
    # VpCtoV past the exponent range: infinite under EXCEPTION_INFINITY's
    # "exponent overflow", or zero.
    def read_overflow(sign, infinite)
      Primitive.attr! :hidden
      return build(sign, 0, 0) unless infinite
      raise FloatDomainError, +"exponent overflow" unless exception_mode.nobits?(EXCEPTION_INFINITY)
    
      sign.negative? ? -INFINITY : INFINITY
    end
    
    # AddExponent: a result past the range is infinite or zero, which
    # EXCEPTION_OVERFLOW and EXCEPTION_UNDERFLOW refuse.
    def exponent_overflow(sign)
      Primitive.attr! :hidden
      raise FloatDomainError, +"Exponent overflow" unless exception_mode.nobits?(EXCEPTION_OVERFLOW)
    
      sign.negative? ? -INFINITY : INFINITY
    end
    
    def exponent_underflow(sign)
      Primitive.attr! :hidden
      raise FloatDomainError, +"Exponent underflow" unless exception_mode.nobits?(EXCEPTION_UNDERFLOW)
    
      build(sign, 0, 0)
    end

    # A value from an Integer of digits, with the trailing zeros taken
    # off so that one number has one form.
    def from_int(sign, digits, exponent)
      Primitive.attr! :hidden
      return build(sign, 0, 0) if digits.zero?

      while (digits % 10).zero?
        digits /= 10
      end
      return exponent_overflow(sign) if exponent > EXPONENT_MAX
      return exponent_underflow(sign) if exponent < EXPONENT_MIN

      build(sign, digits, exponent)
    end

    # A Float has no more digits than its own round trip shows, so with
    # no precision given, those are the digits it gives.
    # rb_convert_to_BigDecimal: `digits` is nil when the caller gave none.
    # With exceptions off, only the cases that the C checks answer nil.
    def convert(value, digits, exception)
      Primitive.attr! :hidden
      case value
      when nil, true, false
        exception ? raise(TypeError, "can't convert #{value.inspect} into BigDecimal") : nil
      when BigDecimal then checked(digits ? value.send(:copy) : value)
      when Integer then from_int(value.negative? ? -1 : 1, value.abs, value.abs.to_s.length)
      when Float then from_float(value, digits, exception)
      when Rational
        return BigDecimal(value.numerator).div(value.denominator, digits) if digits
        exception ? raise(ArgumentError, +"can't omit precision for a Rational.") : nil
      when Complex
        return convert(value.real, digits, exception) if value.imaginary.zero?
        exception ? raise(ArgumentError, +"Unable to make a BigDecimal from non-zero imaginary number") : nil
      else
        text = value.is_a?(String) ? value : String.try_convert(value)
        return c_text(text, exception) && read(text, true, exception) if text
        exception ? raise(TypeError, "can't convert #{value.class} into BigDecimal") : nil
      end
    end
    
    # rb_float_convert_to_BigDecimal: NaN, the infinities and the zeros are
    # the shared values; other digits come from the shortest form that
    # reads back, or rounded to `digits` (dtoa's modes 0 and 2), of which
    # the C keeps at most 16, cut off with no rounding.
    def from_float(value, digits, exception = true)
      Primitive.attr! :hidden
      return checked(value.nan? ? NAN : (value.positive? ? INFINITY : NEGATIVE_INFINITY)) unless value.finite?
      return (1 / value).negative? ? NEGATIVE_ZERO : POSITIVE_ZERO if value.zero?
      if digits && digits > DOUBLE_FIG
        return nil unless exception
    
        raise ArgumentError, +"precision too large."
      end
    
      text = digits.nil? || digits.zero? ? value.abs.to_s : format("%.*e", digits - 1, value.abs)
      mantissa, power = text.split("e")
      whole, fraction = mantissa.split(".")
      figures = "#{whole}#{fraction}".sub(/\A0+/, "")
      point = whole.length + power.to_i - ("#{whole}#{fraction}".length - figures.length)
      from_int(value.negative? ? -1 : 1, figures[0, DOUBLE_FIG].to_i, point)
    end

    # CheckGetValue: a value that is not finite, which the modes refuse.
    def checked(value)
      Primitive.attr! :hidden
      unless value.finite?
        bit = value.nan? ? EXCEPTION_NaN : EXCEPTION_INFINITY
        raise FloatDomainError, refused(value) unless exception_mode.nobits?(bit)
      end
      value
    end
  end

  def nan? = @special == :nan

  def infinite? = @special == :infinity ? @sign : nil

  def finite? = @special.nil?

  def zero? = finite? && @digits.zero?

  def nonzero? = zero? ? nil : self

  def sign
    return SIGN_NaN if nan?
    return @sign * SIGN_POSITIVE_INFINITE if @special == :infinity
    return @sign * SIGN_POSITIVE_ZERO if @digits.zero?

    @sign * SIGN_POSITIVE_FINITE
  end

  def exponent = finite? && !@digits.zero? ? @exp : 0

  # Every digit from the first that counts to the last, which is more
  # than the significant ones when the value has zeros to hold place.
  # VpCountPrecisionAndScale counts in a signed word, which wraps for an
  # exponent near the bottom of the range: the C's count is the one kept.
  def precision
    return 0 unless finite? && !@digits.zero?

    signed_word([@exp, @exp.negative? ? n_significant_digits - @exp : n_significant_digits].max)
  end

  def n_significant_digits = finite? && !@digits.zero? ? @digits.to_s.length : 0

  def scale = finite? ? signed_word([n_significant_digits - @exp, 0].max) : 0

  def precision_scale = [precision, scale]

  # The point moved `n` places to the right, which is what ruby's own
  # square root uses to halve an exponent. BigDecimal_decimal_shift checks
  # a value that is not finite, and the exponent's range.
  def _decimal_shift(n)
    n = Integer.try_convert(given = n) or raise TypeError, no_implicit_conversion(given, "Integer")
    return checked(self) if !finite? || zero? || n.zero?
  
    BigDecimal.from_int(@sign, @digits, @exp + n)
  end

  # BigDecimal_neg and BigDecimal_abs check the value as a result.
  def -@ = checked(negated)

  def +@ = self

  def abs = checked(@sign.negative? ? -self : self)

  # BigDecimal_coerce: a number of the kinds that meet a BigDecimal.
  def coerce(other)
    them = other.is_a?(BigDecimal) ? other : cast(other)
    raise TypeError, "#{BigDecimal.send(:named, other)} can't be coerced into BigDecimal" unless them

    [them, self]
  end

  def +(other) = limited(combine(other, :+))

  def -(other) = limited(combine(other, :-))

  def *(other) = limited(product(other))

  def /(other) = divide(other, 0)
  
  # BigDecimal_quo: a precision of 0 or none is the quotient of `/`.
  def quo(other, digits = (none = true; nil))
    digits = none ? 0 : precision_argument(digits)
    digits.positive? ? divide(other, digits, coerce: false) : divide(other, 0)
  end
  
  # BigDecimal_div2: with no digits, the floored quotient as an Integer,
  # as Float#div gives it; with digits, the quotient rounded there, of
  # another kind of value only one that becomes a BigDecimal.
  def div(other, digits = nil)
    return divide(other, precision_argument(digits), coerce: false) unless digits.nil?
  
    them = cast(other) or return coerced(other, :div)
    checked(divmod_parts(them, false).first).to_i
  end
  
  def modulo(other)
    them = cast(other) or return coerced(other, :%)
    checked(divmod_parts(them, false).last)
  end
  
  alias % modulo
  
  def remainder(other)
    them = cast(other) or return coerced(other, :remainder)
    checked(divmod_parts(them, true).last)
  end
  
  def divmod(other)
    them = cast(other) or return coerced(other, :divmod)
    quotient, rest = divmod_parts(them, false)
    [checked(quotient).to_i, checked(rest)]
  end

  # BigDecimalCmp: NaN is neither less nor more than anything.
  def <(other) = related(other, :<) { |c| c.negative? }
  def <=(other) = related(other, :<=) { |c| !c.positive? }
  def >(other) = related(other, :>) { |c| c.positive? }
  def >=(other) = related(other, :>=) { |c| !c.negative? }

  # BigDecimalCmp: another kind of value compares through its coerce.
  def <=>(other)
    them = cast(other)
    return coerce_compare(other, :<=>) if them.nil?
    return nil if nan? || them.nan?
    return infinite_compare(them) unless finite? && them.finite?
return @sign <=> them.sign_bit if !zero? && !them.zero? && @sign != them.sign_bit
return zero? ? (them.zero? ? 0 : -them.sign_bit) : @sign if zero? || them.zero?
# Two values of one sign with different exponents compare by the
# exponent alone, so no power of ten as wide as the gap is built.
return (@exp <=> them.exp) * @sign if @exp != them.exp

align(them) { |mine, theirs, _| mine <=> theirs }
  end

  def ==(other)
    them = cast(other)
    return coerce_compare(other, :==) ? true : false if them.nil?
    return false if nan? || them.nan?

    (self <=> them)&.zero? || false
  end

  alias === ==
  alias eql? ==

  def hash = [@sign, @digits, @exp, @special].hash

  def to_i
    raise FloatDomainError, "Computation results in 'NaN' (Not a Number)" if nan?
    raise FloatDomainError, "Computation results in '#{@sign.negative? ? '-' : ''}Infinity'" unless finite?

    whole_part
  end

  alias to_int to_i

  # BigDecimal_to_f: a value past a Float's exponents, or one that reads as
  # zero or infinite, underflows or overflows, which the modes refuse.
  def to_f
    return Float::NAN if nan?
    return @sign.negative? ? -Float::INFINITY : Float::INFINITY if @special == :infinity
    return @sign.negative? ? -0.0 : 0.0 if zero?
  
    # VpVtoD's exponent: the word's, in decimal digits.
    word = -(-@exp).div(9) * 9
    return float_overflow if word > Float::MAX_10_EXP + 9
    return float_underflow if word < Float::MIN_10_EXP - Float::DIG
  
    value = to_s.to_f
    return float_underflow if value.zero?
    return float_overflow if value.infinite?
  
    value
  end

  def to_r
    raise FloatDomainError, "Computation results in 'NaN' (Not a Number)" if nan?
    raise FloatDomainError, "Computation results in '#{@sign.negative? ? '-' : ''}Infinity'" unless finite?

    shift = n_significant_digits - @exp
    shift.negative? ? Rational(@sign * @digits * (10**-shift), 1) : Rational(@sign * @digits, 10**shift)
  end

  def truncate(digits = nil) = shortened(digits, ROUND_DOWN)

  def floor(digits = nil) = shortened(digits, ROUND_FLOOR)

  def ceil(digits = nil) = shortened(digits, ROUND_CEILING)

  # `round` with no argument returns an Integer, and so does a place at
  # or left of the point; only a place to the right keeps the decimal.
  # `half:` gives the tie rule as Float#round does; a positional mode
  # gives a rounding of BigDecimal's own.
  HALVES = { up: ROUND_HALF_UP, down: ROUND_HALF_DOWN, even: ROUND_HALF_EVEN }.freeze
  private_constant :HALVES

  # BigDecimal_round: an Integer only for a place below 1 with no mode;
  # a mode, as an argument or as `half:`, keeps a BigDecimal.
  def round(digits = (whole = true; nil), mode = (plain = true; nil), half: (plain_half = true; nil))
    unless plain_half || half.nil?
      name = half.is_a?(Symbol) ? half.to_s : String.try_convert(half)
      mode = HALVES[name&.to_sym] or raise ArgumentError, "invalid rounding mode (#{name || half.inspect})"
    end
    mode = BigDecimal.rounding_mode if mode.nil?
    mode = BigDecimal.send(:rounding, mode)
    place = whole ? 0 : Integer.send(:int_operand, digits)
    raise FloatDomainError, BigDecimal.send(:refused, self) if !finite? && whole && plain && plain_half
    return self unless finite?

    answer = round_to(place, mode)
    !plain_half || !plain || place.positive? ? answer : answer.whole_part
  end

  # What is past the point, which keeps the sign even where nothing
  # is left of it.
  def frac
    return self if !finite? || @exp <= 0
    return BigDecimal.build(@sign, 0, 0) if @exp >= n_significant_digits

    rest = @digits % (10**(n_significant_digits - @exp))
    BigDecimal.from_int(@sign, rest, rest.to_s.length + point)
  end

  def fix = finite? ? truncate(0) : self

  # A precision given here wins over the global limit; 0 keeps the limit.
  def add(other, digits) = with_precision(digits) { |n| combine(other, :+, n) }

  def sub(other, digits) = with_precision(digits) { |n| combine(other, :-, n) }

  def mult(other, digits) = with_precision(digits) { |n| product(other, n) }

  # BigDecimal_to_s: a leading space or `+` for the sign, then digits for
  # the group size, up to the first other character, which is `F` for the
  # plain form. The text is US-ASCII; `inspect` is the same bytes, binary.
  def to_s(format = (none = true; nil)) = shown(format, none)

  # BigDecimal_inspect writes the value itself; it never calls to_s.
  def inspect = shown(nil, true).b

  # The text of to_s and inspect.
  def shown(format, none)
    Primitive.attr! :hidden
    plus = nil
    groups = 0
    plain = false
    if format.is_a?(String)
      chars = format.chars
      plus = chars.shift if chars.first == " " || chars.first == "+"
      chars.each do |c|
        next if c.match?(/\s/)
        unless c.match?(/\d/)
          plain = c.casecmp?("f")
          break
        end
        groups = groups * 10 + c.to_i
      end
    elsif !none
      groups = Integer.send(:int_operand, format)
      raise ArgumentError, +"argument must be positive" unless groups.positive?
    end
    # VpToSpecialString: the sign mark goes only before a positive infinity.
    return (nan? ? +"NaN" : "#{@sign.negative? ? '-' : plus}Infinity").force_encoding(Encoding::US_ASCII) unless finite?

    lead = @sign.negative? ? "-" : plus.to_s
    "#{lead}#{plain ? plain_body(groups) : exponent_body(groups)}".force_encoding(Encoding::US_ASCII)
  end

  def dup = self

  alias clone dup

  # BigDecimal_dump: the precision it keeps, as nine-digit words times
  # nine, then the value.
  def _dump(_limit = nil) = "#{word_count * 9}:#{self}".b

  # BigDecimal_load: the precision before the colon is skipped, and any
  # character there but a digit refuses the data.
  def self._load(text)
    text = String.try_convert(given = text) or raise TypeError, no_implicit_conversion(given, "String")
    raise ArgumentError, +"string contains null byte" if text.include?("\0")
  
    precision, colon, body = text.partition(":")
    raise TypeError, +"load failed: invalid character in the marshaled string" unless precision.match?(/\A\d*\z/)
  
    checked(read(colon.empty? ? "" : body, true))
  end

  def split
    return [0, "NaN", 10, 0] if nan?
return [@sign, "Infinity", 10, 0] unless finite?

    [@sign, @digits.to_s, 10, @exp]
  end

  # The receiver limited to `digits` significant digits, which division
  # and the `add` family both need.
  def round_significant(digits)
    Primitive.attr! :hidden
    return self unless finite?
    return self if digits <= 0 || n_significant_digits <= digits

    drop = n_significant_digits - digits
    kept = shorten(@digits, drop, BigDecimal.rounding_mode, @sign)
    BigDecimal.from_int(@sign, kept, kept.to_s.length + drop + point)
  end

  # The Integer the value truncates to.
  def whole_part
    Primitive.attr! :hidden
    shift = @exp - n_significant_digits
    shift.negative? ? @sign * (@digits / (10**-shift)) : @sign * @digits * (10**shift)
  end

  Primitive.attr! :hidden

  protected

  # Where the value's digits sit: value == digits * 10 ** point.
  def point = @exp - n_significant_digits

  def sign_bit = @sign

  def digits = @digits

  def exp = @exp

  def special = @special

  # The value with the other sign, unchecked: a difference negates its
  # operand as VpAddSub does, by the operation.
  def negated = @special ? BigDecimal.build(-@sign, 0, 0, @special) : BigDecimal.build(-@sign, @digits, @exp)

  private

  # VpGetPrecisionInt: the precision of add, sub and mult.
def with_precision(digits)
  digits = precision_argument(digits)
  answer = yield digits
  return limited(answer) if digits.zero? || !answer.is_a?(BigDecimal)

  answer.round_significant(digits)
end

# check_int_precision: a precision as NUM2LONG reads it, not negative.
def precision_argument(digits)
  n = Integer.try_convert(digits) or raise TypeError, no_implicit_conversion(digits, "Integer")
  raise RangeError, +"bignum too big to convert into 'long'" unless n.bit_length < 64
  raise ArgumentError, +"negative precision" if n.negative?

  n
end

# The exact product, before the global limit. With a precision (mult),
# another kind of value must become a BigDecimal: no coerce.
def product(other, digits = nil)
  them = cast(other, digits || 0) or return digits ? not_coercible(other) : coerced(other, :*)
  return product_special(them) if @special || them.special

  digits = @digits * them.digits
  BigDecimal.from_int(@sign * them.sign_bit, digits, digits.to_s.length + point + them.point)
end

  # A new value with these fields: BigDecimal(value, digits) copies.
  def copy = BigDecimal.build(@sign, @digits, @exp, @special)

  def setup(sign, digits, exponent, special)
    @sign = sign
    @digits = digits
    @exp = exponent
    @special = special
    freeze
  end

  # `n` as a C ssize_t holds it.
  def signed_word(n) = ((n + (2**63)) % (2**64)) - (2**63)

  def checked(value) = BigDecimal.checked(value)
  
  def float_overflow
    raise FloatDomainError, +"BigDecimal to Float conversion" unless BigDecimal.exception_mode.nobits?(EXCEPTION_OVERFLOW)
  
    @sign.negative? ? -Float::INFINITY : Float::INFINITY
  end
  
  def float_underflow
    raise FloatDomainError, +"BigDecimal to Float conversion" unless BigDecimal.exception_mode.nobits?(EXCEPTION_UNDERFLOW)
  
    @sign.negative? ? -0.0 : 0.0
  end

  # The other side as a BigDecimal, or nil when ruby calls coerce on
  # the other side instead.
  # GetBDValueWithPrec: a Rational divides out to the precision of the
  # operation, or of the receiver's words, and never fewer than 32 digits
  # (GetCoercePrec).
  def cast(other, digits = 0)
    case other
    when BigDecimal then other
    when Integer then BigDecimal(other)
    when Rational then BigDecimal(other, [digits.zero? ? word_count * 9 : digits, 2 * DOUBLE_FIG].max)
    when Float then BigDecimal(other, 0)
    end
  end
  
  # cannot_be_coerced_into_BigDecimal.
  def not_coercible(other)
    raise TypeError, "#{BigDecimal.send(:named, other)} can't be coerced into BigDecimal"
  end

  # rb_num_coerce_cmp: the other side's coerce, then `op`, or nil where it
  # has no coerce or its coerce gives nil.
  def coerce_compare(other, op)
    return nil unless other.respond_to?(:coerce)

    pair = other.coerce(self)
    return nil if pair.nil?
    raise TypeError, +"coerce must return [x, y]" unless pair.is_a?(Array) && pair.size == 2

    pair[0].send(op, pair[1])
  end

  def coerced(other, op)
    raise TypeError, "#{BigDecimal.send(:named, other)} can't be coerced into BigDecimal" unless other.respond_to?(:coerce)

    a, b = other.coerce(self)
    a.send(op, b)
  end

  # A comparison: false with NaN on either side, and coerce for an other
  # kind of value, as rb_num_coerce_relop does.
  def related(other, op)
    them = cast(other)
    if them.nil?
      failed = "comparison of BigDecimal with #{BigDecimal.send(:named, other)} failed"
      pair = other.coerce(self) if other.respond_to?(:coerce)
      raise ArgumentError, "#{failed}: coercion was not possible" if pair.nil?

      a, b = pair
      answer = a.send(op, b)
      raise ArgumentError, "#{failed}: comparator returned nil" if answer.nil?

      return answer
    end
    return false if nan? || them.nan?

    yield(self <=> them)
  end

  # BigDecimal_DoDivmod: the quotient, truncated toward zero or floored,
  # and what is left, both exact whatever the limit.
  def divmod_parts(them, truncate)
    return [BigDecimal::NAN, BigDecimal::NAN] if nan? || them.nan? || (!finite? && !them.finite?)
    raise ZeroDivisionError, +"divided by 0" if them.zero?
    return [@sign == them.sign_bit ? BigDecimal::INFINITY : NEGATIVE_INFINITY, BigDecimal::NAN] unless finite?
    return [POSITIVE_ZERO, self] if zero?
    unless them.finite?
      return !truncate && @sign != them.sign_bit ? [BigDecimal.build(-1, 1, 1), them] : [POSITIVE_ZERO, self]
    end
  
    align(them) do |mine, theirs, low|
      quotient = mine.abs / theirs.abs * (@sign * them.sign_bit)
      rest = mine - (quotient * theirs)
      if !truncate && !rest.zero? && @sign != them.sign_bit
        quotient -= 1
        rest += theirs
      end
      [BigDecimal.from_int(quotient.negative? ? -1 : 1, quotient.abs, quotient.abs.to_s.length), sum(rest, low)]
    end
  end
  
  # The nine-digit words that the digits take, aligned at the point.
  def word_count
    return 1 unless finite? && !@digits.zero?

    ((@exp - 1).div(9)) - ((@exp - n_significant_digits).div(9)) + 1
  end

  # BigDecimal_addsub_with_coerce: the sum, with `them` negated for a
  # difference. With a precision, an operand that lies wholly below the
  # other's last digit and the precision takes part as a single unit just
  # below both: it can then only push the rounding, as it does exactly
  # (the C's optimization for a large exponent difference).
  def combine(other, op, digits = nil)
    them = cast(other, digits || 0) or return digits ? not_coercible(other) : coerced(other, op)
  
    them = them.negated if op == :-
    return sum_special(them) if @special || them.special
    return sum_zero(them) if zero? || them.zero?
  
    mine = self
    if digits&.positive?
      if (low = far_below(digits)) && them.exp < low
        them = BigDecimal.build(them.sign_bit, 1, low)
      elsif (low = them.send(:far_below, digits)) && @exp < low
        mine = BigDecimal.build(@sign, 1, low)
      end
    end
    mine.send(:align, them) { |a, b, at| sum(a + b, at) }
  end
  
  # The exponent below which another operand cannot reach the digits that
  # a sum with this one keeps to `digits`.
  def far_below(digits) = [@exp - n_significant_digits, @exp - digits].min - 2
  
  # VpAddSub with a zero operand: the other one, and of two zeros a
  # negative zero only when both are negative.
  def sum_zero(them)
    return them unless them.zero?
    return self unless zero?
  
    BigDecimal.build(@sign.negative? && them.sign_bit.negative? ? -1 : 1, 0, 0)
  end

  # The two values as Integers over one shared power of ten.
  def align(them)
    low = [@exp - n_significant_digits, them.exp - them.n_significant_digits].min
    mine = @sign * @digits * (10**((@exp - n_significant_digits) - low))
    theirs = them.sign_bit * them.digits * (10**((them.exp - them.n_significant_digits) - low))
    yield(mine, theirs, low)
  end

  def sum(total, low)
    return BigDecimal.build(1, 0, 0) if total.zero?

    BigDecimal.from_int(total.negative? ? -1 : 1, total.abs, low + total.abs.to_s.length)
  end

  # A NaN operand comes back as it is, checked as a value; infinities go
  # through VpIsDefOP, which raises "results to" under the modes.
  def sum_special(them)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    return BigDecimal.infinity_result(them.sign_bit) if finite?
    return BigDecimal.infinity_result(@sign) if them.finite? || @sign == them.sign_bit
  
    BigDecimal.nan_result
  end

  def product_special(them)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    return BigDecimal.nan_result if zero? || them.zero?

    BigDecimal.infinity_result(@sign * them.sign_bit)
  end

  def infinite_compare(them)
    return 0 if @special == :infinity && them.special == :infinity && @sign == them.sign_bit
    return @sign if @special == :infinity

    -them.sign_bit
  end

  # `a / b` to `digits` significant digits. With none given, ruby uses
  # the wider operand's own width plus a Float's worth, and never fewer
  # than two of those.
  def divide(other, digits, coerce: true)
    them = cast(other, digits) or return coerce ? coerced(other, :/) : not_coercible(other)
    return divide_special(them) if @special || them.special || them.zero? || zero?

    # BigDecimal_div2's width: the given digits, else the wider operand's
    # plus a Float's, at least two Floats', and at most the limit.
    want = digits
    if want.zero?
      want = [[precision, them.precision].max + DOUBLE_FIG, 2 * DOUBLE_FIG].max
      limit = BigDecimal.precision_limit
      want = limit if limit.positive? && limit < want
    end
    shift = [want + 1 + them.n_significant_digits - n_significant_digits, 0].max
    quotient, rest = (@digits * (10**shift)).divmod(them.digits)
    # A remainder that is left over says the true value lies past the
    # last digit shown, which keeps a rounding from reading it as an
    # exact half.
    quotient += 1 if !rest.zero? && [0, 5].include?(quotient % 10)
    drop = [quotient.to_s.length - want, 0].max
    kept = drop.zero? ? quotient : shorten(quotient, drop, BigDecimal.rounding_mode, @sign)
    answer = BigDecimal.from_int(@sign * them.sign_bit, kept, kept.to_s.length + drop + point - them.point - shift)
    answer
  end

  # Ruby's process-wide limit on how many digits a result keeps.
  def limited(answer)
    limit = BigDecimal.precision_limit
    limit.zero? ? answer : answer.round_significant(limit)
  end

  def divide_special(them)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    return BigDecimal.nan_result if (@special == :infinity && them.special == :infinity) || (zero? && them.zero?)
    return BigDecimal.build(@sign * them.sign_bit, 0, 0) if them.special == :infinity || zero?
    return BigDecimal.zero_divide_result(@sign * them.sign_bit) if them.zero?

    BigDecimal.infinity_result(@sign * them.sign_bit)
  end

  # `floor`, `ceil` and `truncate`: an Integer with no place named, a
  # decimal at the place named.
  def shortened(digits, mode)
    raise FloatDomainError, BigDecimal.send(:refused, self) if !finite? && digits.nil?
    return self unless finite?
    return round_to(digits.to_int, mode) if digits

    round_to(0, mode).whole_part
  end

  # The receiver with `digits` places kept past the point, which is
  # what floor, ceil, truncate and round all come down to.
  def round_to(digits, mode)
    drop = n_significant_digits - @exp - digits
    return self if drop <= 0 || @digits.zero?

    kept = shorten(@digits, drop, mode, @sign)
    BigDecimal.from_int(@sign, kept, kept.to_s.length - digits)
  end

  # `digits` with its last `drop` digits taken off, rounded the way
  # `mode` says; `sign` decides which way ceiling and floor go.
  def shorten(digits, drop, mode, sign)
    scale = 10**drop
    kept = digits / scale
    rest = digits % scale
    return kept if rest.zero?

    kept + (round_up?(kept, rest, scale, mode, sign) ? 1 : 0)
  end

  def round_up?(kept, rest, scale, mode, sign)
    case mode
    when ROUND_DOWN then false
    when ROUND_UP then true
    when ROUND_CEILING then sign.positive?
    when ROUND_FLOOR then sign.negative?
    when ROUND_HALF_DOWN then rest * 2 > scale
    when ROUND_HALF_EVEN then rest * 2 > scale || (rest * 2 == scale && kept.odd?)
    else rest * 2 >= scale
    end
  end

  def grouped(text, size) = size.zero? || size >= text.length ? text : text.scan(/.{1,#{size}}/).join(" ")

  # An integer part groups from the right, a fraction from the left,
  # which is how ruby writes them.
  def grouped_whole(text, size)
    return text if size.zero? || size >= text.length

    text.reverse.scan(/.{1,#{size}}/).map(&:reverse).reverse.join(" ")
  end

  def exponent_body(groups)
    return "0.0" if zero?

    "0.#{grouped(@digits.to_s, groups)}e#{@exp}"
  end

  def plain_body(groups)
    return "0.0" if zero?

    text = @digits.to_s
    if @exp <= 0
      "0.#{grouped(('0' * -@exp) + text, groups)}"
    elsif @exp >= text.length
      "#{grouped_whole(text + ('0' * (@exp - text.length)), groups)}.0"
    else
      "#{grouped_whole(text[0, @exp], groups)}.#{grouped(text[@exp..], groups)}"
    end
  end
end

class << BigDecimal
  undef_method :new
end

BigDecimal.const_set(:INFINITY, BigDecimal.build(1, 0, 0, :infinity))
BigDecimal.const_set(:NAN, BigDecimal.build(1, 0, 0, :nan))
# The shared values that the C makes once: a Float's zeros and infinities.
BigDecimal.const_set(:NEGATIVE_INFINITY, BigDecimal.build(-1, 0, 0, :infinity))
BigDecimal.const_set(:POSITIVE_ZERO, BigDecimal.build(1, 0, 0))
BigDecimal.const_set(:NEGATIVE_ZERO, BigDecimal.build(-1, 0, 0))
BigDecimal.send(:private_constant, :NEGATIVE_INFINITY, :POSITIVE_ZERO, :NEGATIVE_ZERO)

module Kernel
  # `BigDecimal(value)`: text is read as it is written, an Integer is
  # exact, and a Float or a Rational needs a precision because their
  # own digits do not stop where a decimal's do.
  def BigDecimal(value, digits = (omitted = true; nil), exception: true)
    raise ArgumentError, "expected true or false as exception: #{exception.inspect}" unless exception == true || exception == false
  
    unless omitted
      digits = Integer.try_convert(given = digits) or raise TypeError, no_implicit_conversion(given, "Integer")
      if digits.negative?
        return nil unless exception
  
        raise ArgumentError, +"negative precision"
      end
    end
    BigDecimal.send(:convert, value, digits, exception)
  end

  module_function :BigDecimal
  public :BigDecimal
end
