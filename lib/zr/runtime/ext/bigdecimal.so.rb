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
  # The widest exponent a value keeps: past it a value is infinite, and
  # below its negative a value is zero.
  EXPONENT_MAX = (2**63) - 1
  private_constant :DOUBLE_FIG, :EXPONENT_MAX

  class << self
    # `mode(ROUND_MODE)` reads or writes the rounding; every other
    # selector is a bit in the word that says which results raise.
    def mode(selector, value = nil)
      @mode ||= ROUND_HALF_UP
      @flags ||= 0
      return @mode = value.nil? ? @mode : rounding(value) if selector == ROUND_MODE
      return @flags if value.nil?
      raise ArgumentError, +"second argument must be true or false" unless value == true || value == false

      @flags = value ? @flags | selector : @flags & ~selector
    end

    # The limit returns its old value, so a caller can restore it.
    def limit(digits = nil)
      @limit ||= 0
      was = @limit
      @limit = digits.to_int unless digits.nil?
      was
    end

    def double_fig = DOUBLE_FIG

    def save_rounding_mode
      was = mode(ROUND_MODE)
      yield
    ensure
      mode(ROUND_MODE, was)
    end

    def save_limit
      was = limit
      yield
    ensure
      limit(was)
    end

    def save_exception_mode
      was = mode(EXCEPTION_ALL)
      yield
    ensure
      mode(EXCEPTION_ALL, false)
      mode(was, true) unless was.zero?
    end

    # The results that ruby refuses to return when the matching bit is
    # set in the mode word.
    # A NaN that an operation makes "results to" NaN; one that an operand
    # brings in "results in" it, as VpException words the two.
    def nan_result(given = false)
      Primitive.attr! :hidden
      unless (mode(EXCEPTION_ALL) & EXCEPTION_NaN).zero?
        raise FloatDomainError, given ? refused(NAN) : +"Computation results to 'NaN'"
      end

      NAN
    end

    def infinity_result(sign, word = "to")
      Primitive.attr! :hidden
      unless (mode(EXCEPTION_ALL) & EXCEPTION_INFINITY).zero?
        raise FloatDomainError, "Computation results #{word} '#{sign.negative? ? '-' : ''}Infinity'"
      end

      sign.negative? ? -INFINITY : INFINITY
    end

    def zero_divide_result(sign)
      Primitive.attr! :hidden
      raise FloatDomainError, +"Divide by zero" unless (mode(EXCEPTION_ALL) & EXCEPTION_ZERODIVIDE).zero?

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
    def read(source, strict)
      Primitive.attr! :hidden
      # An underscore stands between two digits, or after the last one.
      text = source.gsub(/(?<=\d)_(?=\d|\s*\z)/, "")
      if (special = text[/\A\s*(NaN|[-+]?Infinity)\s*\z/, 1])
        value = special == "NaN" ? NAN : (special.start_with?("-") ? -INFINITY : INFINITY)
        bit = value.nan? ? EXCEPTION_NaN : EXCEPTION_INFINITY
        raise FloatDomainError, refused(value) unless (mode(EXCEPTION_ALL) & bit).zero?

        return value
      end

      match = /\A\s*([-+]?)(\d*)(?:\.(\d*))?(?:[eEdD]([-+]?\d+))?/.match(text)
      whole = match[2].to_s
      fraction = match[3].to_s
      empty = whole.empty? && fraction.empty?
      raise ArgumentError, "invalid value for BigDecimal(): #{source.inspect}" if strict && (empty || !text[match.end(0)..].to_s.strip.empty?)
      return build(1, 0, 0) if empty

      digits = "#{whole}#{fraction}"
      lead = digits.length - digits.sub(/\A0+/, "").length
      from_int(match[1] == "-" ? -1 : 1, digits.to_i, whole.length + match[4].to_i - lead)
    end

    # A value from an Integer of digits, with the trailing zeros taken
    # off so that one number has one form.
    def from_int(sign, digits, exponent)
      Primitive.attr! :hidden
      return build(sign, 0, 0) if digits.zero?

      while (digits % 10).zero?
        digits /= 10
      end
      return infinity_result(sign, "in") if exponent > EXPONENT_MAX
      return build(sign, 0, 0) if exponent < -EXPONENT_MAX

      build(sign, digits, exponent)
    end

    # A Float has no more digits than its own round trip shows, so with
    # no precision given, those are the digits it gives.
    def from_float(value, precision)
      Primitive.attr! :hidden
      raise ArgumentError, "negative precision" if precision.negative?
      return value.positive? ? INFINITY : -INFINITY if value.infinite?
      return NAN if value.nan?
      raise ArgumentError, "precision too large." if precision > DOUBLE_FIG
      return read(value.to_s, false) if precision.zero?

      read(format("%.*e", [precision, 17].max, value), false).round_significant(precision)
    end

    def from_rational(value, precision)
      Primitive.attr! :hidden
      raise ArgumentError, "can't omit precision for a Rational." if precision.zero?

      BigDecimal(value.numerator).div(BigDecimal(value.denominator), precision)
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
  def precision
    return 0 unless finite? && !@digits.zero?

    [@exp, @exp.negative? ? n_significant_digits - @exp : n_significant_digits].max
  end

  def n_significant_digits = finite? && !@digits.zero? ? @digits.to_s.length : 0

  def scale = finite? ? [n_significant_digits - @exp, 0].max : 0

  def precision_scale = [precision, scale]

  # The point moved `n` places to the right, which is what ruby's own
  # square root uses to halve an exponent.
  def _decimal_shift(n) = finite? ? BigDecimal.build(@sign, @digits, @exp + n) : self

  def -@ = @special ? BigDecimal.build(-@sign, 0, 0, @special) : BigDecimal.build(-@sign, @digits, @exp)

  def +@ = self

  def abs = @sign.negative? ? -self : self

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

  def quo(other, digits = 0) = divide(other, digits.to_int)

  # With no digits given, this is the Integer quotient, as ruby's own
  # `div` is; with digits it is the division rounded there.
  def div(other, digits = nil)
    return divide(other, digits.to_int) if digits

    them = cast(other) or return coerced(other, :div)
    quotient, = floored(them)
    quotient
  end

  # BigDecimal_DoDivmod: the floor of the quotient and what is left. A
  # finite value over an infinite one is 0 with itself left, or -1 with
  # the infinity left where their signs differ.
  def modulo(other)
    them = cast(other) or return coerced(other, :modulo)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    raise ZeroDivisionError, +"divided by 0" if them.zero?
    return BigDecimal.nan_result unless finite?
    return floored(them).last unless them.finite?

    self - (them * BigDecimal((self / them).floor))
  end

  alias % modulo

  def remainder(other)
    them = cast(other) or return coerced(other, :remainder)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    raise ZeroDivisionError, +"divided by 0" if them.zero?
    return BigDecimal.nan_result unless finite?
    return self unless them.finite?

    self - (them * BigDecimal((self / them).truncate))
  end

  def divmod(other)
    them = cast(other) or return coerced(other, :divmod)
    floored(them)
  end

  # BigDecimalCmp: NaN is neither less nor more than anything.
  def <(other) = related(other, :<) { |c| c.negative? }
  def <=(other) = related(other, :<=) { |c| !c.positive? }
  def >(other) = related(other, :>) { |c| c.positive? }
  def >=(other) = related(other, :>=) { |c| !c.negative? }

  # BigDecimalCmp: another kind of value compares through its coerce.
  def <=>(other)
    them = cast(other)
    if them.nil?
      return nil unless other.respond_to?(:coerce)

      a, b = other.coerce(self)
      return a <=> b
    end
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
    return false if them.nil? || nan? || them.nan?

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

  def to_f
    return Float::NAN if nan?
    return @sign.negative? ? -Float::INFINITY : Float::INFINITY if @special == :infinity

    to_s.to_f
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
    mode = BigDecimal.mode(ROUND_MODE) if mode.nil?
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
  def add(other, digits) = with_precision(digits) { combine(other, :+) }

  def sub(other, digits) = with_precision(digits) { combine(other, :-) }

  def mult(other, digits) = with_precision(digits) { product(other) }

  # BigDecimal_to_s: a leading space or `+` for the sign, then digits for
  # the group size, up to the first other character, which is `F` for the
  # plain form. The text is US-ASCII; `inspect` is the same bytes, binary.
  def to_s(format = (none = true; nil)) = shown(format, none)

  # BigDecimal_inspect writes the value itself; it never calls to_s.
  def inspect = shown(nil, true).b

  # The text of to_s and inspect.
  def shown(format, none)
    Primitive.attr! :hidden
    return (nan? ? +"NaN" : "#{@sign.negative? ? '-' : ''}Infinity").force_encoding(Encoding::US_ASCII) unless finite?

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
      raise TypeError, no_implicit_conversion(format, "Integer") if format.nil? || !format.respond_to?(:to_int)

      groups = format.to_int
      raise ArgumentError, "argument must be positive" if groups < 0
    end
    lead = @sign.negative? ? "-" : plus.to_s
    "#{lead}#{plain ? plain_body(groups) : exponent_body(groups)}".force_encoding(Encoding::US_ASCII)
  end

  def dup = self

  alias clone dup

  # BigDecimal_dump: the precision it keeps, as nine-digit words times
  # nine, then the value.
  def _dump(_limit = nil) = "#{word_count * 9}:#{self}".b

  def self._load(text) = BigDecimal(text.split(":", 2).last)

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
    kept = shorten(@digits, drop, BigDecimal.mode(ROUND_MODE), @sign)
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

  private

  # VpGetPrecisionInt: the precision of add, sub and mult.
def with_precision(digits)
  raise TypeError, no_implicit_conversion(digits, "Integer") if digits.nil?

  digits = Integer.send(:int_operand, digits)
  raise ArgumentError, "negative precision" if digits.negative?

  answer = yield
  return limited(answer) if digits.zero? || !answer.is_a?(BigDecimal)

  answer.round_significant(digits)
end

# The exact product, before the global limit.
def product(other)
  them = cast(other)
  return coerced(other, :*) unless them
  return product_special(them) if @special || them.special

  digits = @digits * them.digits
  BigDecimal.from_int(@sign * them.sign_bit, digits, digits.to_s.length + point + them.point)
end

  def setup(sign, digits, exponent, special)
    @sign = sign
    @digits = digits
    @exp = exponent
    @special = special
    freeze
  end

  # The other side as a BigDecimal, or nil when ruby calls coerce on
  # the other side instead.
  def cast(other)
    case other
    when BigDecimal then other
    when Integer then BigDecimal(other)
    when Rational then BigDecimal(other, [precision + DOUBLE_FIG, 2 * DOUBLE_FIG].max)
    when Float then BigDecimal(other, 0)
    end
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

  # The floor of the quotient, and what is left, for div, divmod and %.
  def floored(them)
    raise FloatDomainError, BigDecimal.send(:refused, self) if nan?
    raise ZeroDivisionError, +"divided by 0" if them.zero?
    raise FloatDomainError, BigDecimal.send(:refused, BigDecimal::NAN) if them.nan? || (!finite? && !them.finite?)
    raise FloatDomainError, BigDecimal.send(:refused, self) unless finite?
    return [0, self] if zero? && !them.finite?
    return (@sign == them.sign_bit ? [0, self] : [-1, them]) unless them.finite?

    quotient = (self / them).floor
    [quotient, self - (them * BigDecimal(quotient))]
  end

  # The nine-digit words that the digits take, aligned at the point.
  def word_count
    return 1 unless finite? && !@digits.zero?

    ((@exp - 1).div(9)) - ((@exp - n_significant_digits).div(9)) + 1
  end

  def combine(other, op)
    them = cast(other)
    return coerced(other, op) unless them

    them = -them if op == :-
    return sum_special(them) if @special || them.special

    align(them) { |mine, theirs, low| sum(mine + theirs, low) }
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

  def sum_special(them)
    return BigDecimal.nan_result(true) if nan? || them.nan?
    return them if finite?
    return self if them.finite? || @sign == them.sign_bit

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
  def divide(other, digits)
    them = cast(other)
    return coerced(other, :/) unless them
    return divide_special(them) if @special || them.special || them.zero? || zero?

    want = digits.positive? ? digits : [[precision, them.precision].max + DOUBLE_FIG, 2 * DOUBLE_FIG].max
    shift = [want + 1 + them.n_significant_digits - n_significant_digits, 0].max
    quotient, rest = (@digits * (10**shift)).divmod(them.digits)
    # A remainder that is left over says the true value lies past the
    # last digit shown, which keeps a rounding from reading it as an
    # exact half.
    quotient += 1 if !rest.zero? && [0, 5].include?(quotient % 10)
    drop = [quotient.to_s.length - want, 0].max
    kept = drop.zero? ? quotient : shorten(quotient, drop, BigDecimal.mode(ROUND_MODE), @sign)
    answer = BigDecimal.from_int(@sign * them.sign_bit, kept, kept.to_s.length + drop + point - them.point - shift)
    digits.positive? ? answer : limited(answer)
  end

  # Ruby's process-wide limit on how many digits a result keeps.
  def limited(answer)
    BigDecimal.limit.zero? ? answer : answer.round_significant(BigDecimal.limit)
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

  def grouped(text, size) = size.zero? ? text : text.scan(/.{1,#{size}}/).join(" ")

  # An integer part groups from the right, a fraction from the left,
  # which is how ruby writes them.
  def grouped_whole(text, size)
    return text if size.zero?

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

module Kernel
  # `BigDecimal(value)`: text is read as it is written, an Integer is
  # exact, and a Float or a Rational needs a precision because their
  # own digits do not stop where a decimal's do.
  def BigDecimal(value, precision = 0, exception: true)
    case value
    when BigDecimal then value
    when Integer then BigDecimal.from_int(value.negative? ? -1 : 1, value.abs, value.abs.to_s.length)
    when Float then BigDecimal.from_float(value, precision)
    when Rational then BigDecimal.from_rational(value, precision)
    when Complex
      raise ArgumentError, "Unable to make a BigDecimal from non-zero imaginary number" unless value.imaginary.zero?

      BigDecimal(value.real, precision, exception: exception)
    when String
      text = BigDecimal.send(:c_text, value, exception) or return nil
      BigDecimal.read(text, true)
    when nil then raise TypeError, "can't convert nil into BigDecimal"
    else
      raise TypeError, "can't convert #{conversion_name(value)} into BigDecimal" unless value.respond_to?(:to_str)

      BigDecimal(value.to_str, precision, exception: exception)
    end
  rescue ArgumentError, TypeError, FloatDomainError
    raise if exception

    nil
  end

  module_function :BigDecimal
  public :BigDecimal
end
