# frozen_string_literal: true

# Decimal numbers with as many digits as the caller asks for.
#
# A value is `sign * digits * 10 ** (exponent - digit count)`, so the
# printed form `0.<digits>e<exponent>` reads straight off the fields.
# `digits` is an Integer with no trailing zero, which makes equality
# and the printed form one and the same question.
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
  EXCEPTION_NaN = 2
  EXCEPTION_UNDERFLOW = 4
  EXCEPTION_OVERFLOW = 1
  EXCEPTION_ZERODIVIDE = 16
  EXCEPTION_ALL = 255
  SIGN_NaN = 0
  SIGN_POSITIVE_ZERO = 1
  SIGN_NEGATIVE_ZERO = -1
  SIGN_POSITIVE_FINITE = 2
  SIGN_NEGATIVE_FINITE = -2
  SIGN_POSITIVE_INFINITE = 3
  SIGN_NEGATIVE_INFINITE = -3
  INFINITY = nil
  NAN = nil
  VERSION = "3.2.4"

  # Ruby holds its digits nine at a time, and every count it reports is
  # rounded up to that.
  BASE_FIG = 9
  private_constant :BASE_FIG

  # A division with no precision asked for still stops somewhere: ruby
  # gives it twice the working width of the wider operand.
  DIVIDE_FIG = 2 * BASE_FIG
  private_constant :DIVIDE_FIG

  class << self
    def mode(selector, value = nil)
      @mode ||= ROUND_HALF_UP
      return @mode unless selector == ROUND_MODE

      @mode = value.nil? ? @mode : rounding(value)
    end

    def limit(digits = nil)
      @limit ||= 0
      @limit = digits unless digits.nil?
      @limit
    end

    def double_fig = 16

    def save_rounding_mode
      was = mode(ROUND_MODE)
      yield
    ensure
      mode(ROUND_MODE, was)
    end

    alias save_limit save_rounding_mode
    alias save_exception_mode save_rounding_mode

    # The rounding a name or a number stands for.
    def rounding(value)
      return value if value.is_a?(Integer) && (ROUND_UP..ROUND_HALF_EVEN).cover?(value)

      name = value.is_a?(String) || value.is_a?(Symbol) ? value.to_sym : nil
      found = { up: ROUND_UP, down: ROUND_DOWN, truncate: ROUND_DOWN, half_up: ROUND_HALF_UP,
                default: ROUND_HALF_UP, half_down: ROUND_HALF_DOWN, half_even: ROUND_HALF_EVEN,
                banker: ROUND_HALF_EVEN, ceiling: ROUND_CEILING, ceil: ROUND_CEILING,
                floor: ROUND_FLOOR }[name]
      raise ArgumentError, "invalid rounding mode (#{value.inspect})" unless found

      found
    end

    # The one way an instance is built: nothing else writes the fields.
    def build(sign, digits, exponent, special = nil)
      value = allocate
      value.send(:setup, sign, digits, exponent, special)
      value
    end

    def interpret_loosely(source) = Parse.read(source.to_s, false)
  end

  # Reading a decimal out of text, which `BigDecimal()` and `to_d` both
  # need and which differ only in what they do with trailing rubbish.
  module Parse
    PATTERN = /\A\s*([-+]?)(\d*)(?:\.(\d*))?(?:[eEdD]([-+]?\d+))?/

    # `strict` refuses text with anything left over, which is what
    # `BigDecimal("1x")` does; loose reading keeps what it understood.
    def self.read(source, strict)
      text = source.tr("_", "")
      return special(text, strict) if text.match?(/\A\s*[-+]?(NaN|Infinity)\s*\z/i)

      match = PATTERN.match(text)
      whole = match[2].to_s
      fraction = match[3].to_s
      rest = text[match.end(0)..].to_s
      if strict && (!rest.strip.empty? || (whole.empty? && fraction.empty?))
        raise ArgumentError, "invalid value for BigDecimal(): #{source.inspect}"
      end
      return BigDecimal.build(1, 0, 0) if whole.empty? && fraction.empty?

      sign = match[1] == "-" ? -1 : 1
      BigDecimal.send(:from_digits, sign, "#{whole}#{fraction}", whole.length + match[4].to_i)
    end

    def self.special(text, strict)
      name = text.strip
      sign = name.start_with?("-") ? -1 : 1
      body = name.delete_prefix("-").delete_prefix("+")
      if body.casecmp("nan").zero?
        raise FloatDomainError, "NaN" if strict && (BigDecimal.mode(BigDecimal::EXCEPTION_NaN) != 0)

        return BigDecimal.build(1, 0, 0, :nan)
      end
      BigDecimal.build(sign, 0, 0, :infinity)
    end
  end
  private_constant :Parse

  def initialize(*) = raise(NoMethodError, "undefined method 'new' for class 'BigDecimal'")

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

  def precs = [precision, precision]

  def precision = finite? ? round_up_fig(n_significant_digits) : 0

  def n_significant_digits = finite? ? significant.length : 0

  def scale = finite? ? [n_significant_digits - @exp, 0].max : 0

  def -@ = @special ? BigDecimal.build(-@sign, 0, 0, @special) : BigDecimal.build(-@sign, @digits, @exp)

  def +@ = self

  def abs = @sign.negative? ? -self : self

  def coerce(other) = [BigDecimal(other), self]

  def +(other) = combine(other, :+)

  def -(other) = combine(other, :-)

  def *(other)
    them = cast(other)
    return coerced(other, :*) unless them
    return product_special(them) if @special || them.special

    BigDecimal.send(:from_int, @sign * them.sign_bit, @digits * them.digits, @exp + them.exp)
  end

  def /(other) = divide(other, 0)

  alias quo /

  def div(other, digits = nil)
    return (self / other).floor if digits.nil?
    return divide(other, digits) if digits.positive?

    (self / other).floor
  end

  def modulo(other)
    them = cast(other) or return coerced(other, :modulo)
    return BigDecimal.build(1, 0, 0, :nan) if !finite? || !them.finite? || them.zero?

    self - (them * (self / them).floor)
  end

  alias % modulo

  def remainder(other)
    them = cast(other) or return coerced(other, :remainder)
    return BigDecimal.build(1, 0, 0, :nan) if !finite? || !them.finite? || them.zero?

    self - (them * (self / them).truncate)
  end

  def divmod(other)
    q = div(other)
    [q, self - (cast(other) * q)]
  end

  def **(other) = power(other)

  alias power **

  def <=>(other)
    them = cast(other)
    return nil if them.nil? || nan? || (them.finite? == false && them.nan?)
    return infinite_compare(them) unless finite? && them.finite?
    return @sign <=> them.sign_bit if zero? != them.zero? || sign_of_pair(them)

    scaled_compare(them)
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
    raise FloatDomainError, to_s if !finite?

    truncate.to_int_value
  end

  alias to_int to_i

  def to_f
    return Float::NAN if nan?
    return @sign.negative? ? -Float::INFINITY : Float::INFINITY if @special == :infinity

    to_s.to_f
  end

  def to_r
    raise FloatDomainError, to_s unless finite?

    shift = n_significant_digits - @exp
    shift.negative? ? Rational(@sign * @digits * (10**-shift), 1) : Rational(@sign * @digits, 10**shift)
  end

  def to_d = self

  def truncate(digits = nil) = rounded(digits, ROUND_DOWN)

  def floor(digits = nil) = rounded(digits, ROUND_FLOOR)

  def ceil(digits = nil) = rounded(digits, ROUND_CEILING)

  def round(digits = nil, half = nil)
    mode = half.nil? ? BigDecimal.mode(ROUND_MODE) : BigDecimal.rounding(half)
    rounded(digits, mode)
  end

  def frac = finite? ? self - truncate : self

  def fix = finite? ? truncate : self

  def sqrt(digits = 0)
    raise FloatDomainError, "sqrt of NaN" if nan?
    raise FloatDomainError, "sqrt of negative value" if @sign.negative? && !zero?
    return self if zero? || @special

    newton_sqrt([digits.to_int, precision, DIVIDE_FIG].max)
  end

  def add(other, digits) = digits.zero? ? self + other : (self + other).round_significant(digits)

  def sub(other, digits) = digits.zero? ? self - other : (self - other).round_significant(digits)

  def mult(other, digits) = digits.zero? ? self * other : (self * other).round_significant(digits)

  def to_s(format = nil)
    return nan? ? "NaN" : "#{@sign.negative? ? '-' : ''}Infinity" unless finite?

    shape = Shape.new(format)
    body = shape.plain? ? plain_body(shape.groups) : exponent_body(shape.groups)
    "#{shape.lead(@sign)}#{body}"
  end

  alias inspect to_s

  def dup = self

  alias clone dup

  def _dump(_limit = nil) = "#{precision}:#{self}"

  def self._load(text) = BigDecimal(text.split(":", 2).last)

  def split
    return [sign <=> 0, "NaN", 10, 0] if nan?

    [@sign, significant, 10, @exp]
  end

  def to_int_value
    Primitive.attr! :hidden
    shift = @exp - n_significant_digits
    shift.negative? ? @sign * (@digits / (10**-shift)) : @sign * @digits * (10**shift)
  end

  # The receiver kept to `digits` significant digits, which the `add`
  # family and division both ask for.
  def round_significant(digits)
    Primitive.attr! :hidden
    return self unless finite?
    return self if digits <= 0 || n_significant_digits <= digits

    BigDecimal.send(:from_int, @sign, apply_rounding(@digits, n_significant_digits - digits, BigDecimal.mode(ROUND_MODE), @sign), @exp)
  end

  protected

  def sign_bit = @sign

  def digits = @digits

  def exp = @exp

  def special = @special

  private

  def setup(sign, digits, exponent, special)
    @sign = sign
    @digits = digits
    @exp = exponent
    @special = special
    freeze
  end

  # A value from its digit text: the digits as an Integer, and where
  # the point sits counted from the first digit.
  def self.from_digits(sign, text, point)
    lead = text.length - text.sub(/\A0+/, "").length
    from_int(sign, text.to_i, point - lead)
  end
  private_class_method :from_digits

  # A value from an Integer of digits, with the trailing zeros taken
  # off so that one number has one form.
  def self.from_int(sign, digits, exponent)
    return build(sign, 0, 0) if digits.zero?

    while (digits % 10).zero?
      digits /= 10
    end
    build(sign, digits, exponent)
  end
  private_class_method :from_int

  def significant
    Primitive.attr! :hidden
    @digits.zero? ? "0" : @digits.to_s
  end

  def round_up_fig(n) = n.zero? ? 0 : ((n + BASE_FIG - 1) / BASE_FIG) * BASE_FIG

  # The other side as a BigDecimal, or nil when ruby would rather ask
  # the other side to coerce.
  def cast(other)
    case other
    when BigDecimal then other
    when Integer then BigDecimal(other)
    when Rational then BigDecimal(other, [precision, DIVIDE_FIG].max)
    when Float then BigDecimal(other, 0)
    end
  end

  def coerced(other, op)
    raise TypeError, "#{other.class} can't be coerced into BigDecimal" unless other.respond_to?(:coerce)

    a, b = other.coerce(self)
    a.send(op, b)
  end

  def combine(other, op)
    them = cast(other)
    return coerced(other, op) unless them
    return sum_special(them, op) if @special || them.special

    them = -them if op == :-
    align(them) { |mine, theirs, exponent| BigDecimal.send(:from_int, 1, 0, 0) && sum(mine, theirs, exponent) }
  end

  # The two values as Integers over one shared exponent.
  def align(them)
    low = [@exp - n_significant_digits, them.exp - them.n_significant_digits].min
    mine = @sign * @digits * (10**((@exp - n_significant_digits) - low))
    theirs = them.sign_bit * them.digits * (10**((them.exp - them.n_significant_digits) - low))
    yield(mine, theirs, low)
  end

  def sum(mine, theirs, low)
    total = mine + theirs
    return BigDecimal.build(1, 0, 0) if total.zero?

    BigDecimal.send(:from_int, total.negative? ? -1 : 1, total.abs, low + total.abs.to_s.length)
  end

  def sum_special(them, op)
    them = -them if op == :-
    return BigDecimal.build(1, 0, 0, :nan) if nan? || them.nan?
    return them if finite?
    return self if them.finite?
    return self if @sign == them.sign_bit

    BigDecimal.build(1, 0, 0, :nan)
  end

  def product_special(them)
    return BigDecimal.build(1, 0, 0, :nan) if nan? || them.nan?
    return BigDecimal.build(1, 0, 0, :nan) if zero? || them.zero?

    BigDecimal.build(@sign * them.sign_bit, 0, 0, :infinity)
  end

  def sign_of_pair(them) = @sign != them.sign_bit && !(zero? && them.zero?)

  def infinite_compare(them)
    return 0 if @special == :infinity && them.special == :infinity && @sign == them.sign_bit
    return @sign if @special == :infinity

    -them.sign_bit
  end

  def scaled_compare(them)
    align(them) { |mine, theirs, _| mine <=> theirs }
  end

  # `a / b` to `digits` significant digits, or to twice the wider
  # operand's width when the caller names none.
  def divide(other, digits)
    them = cast(other)
    return coerced(other, :/) unless them
    return divide_special(them) if @special || them.special || them.zero?
    return BigDecimal.build(@sign * them.sign_bit, 0, 0) if zero?

    want = digits.positive? ? digits : [precision, them.precision, DIVIDE_FIG].max
    shift = want + 1 + them.n_significant_digits - n_significant_digits
    quotient = (@digits * (10**shift)) / them.digits
    exponent = @exp - them.exp + n_significant_digits - them.n_significant_digits - shift + quotient.to_s.length
    BigDecimal.send(:from_int, @sign * them.sign_bit, apply_rounding(quotient, quotient.to_s.length - want, ROUND_HALF_UP, 1), exponent)
  end

  def divide_special(them)
    return BigDecimal.build(1, 0, 0, :nan) if nan? || them.nan?
    return BigDecimal.build(1, 0, 0, :nan) if @special == :infinity && them.special == :infinity
    return BigDecimal.build(@sign * them.sign_bit, 0, 0) if them.special == :infinity
    return BigDecimal.build(@sign * them.sign_bit, 0, 0, :infinity) if @special == :infinity
    raise ZeroDivisionError, "divided by 0" if them.zero? && zero?

    BigDecimal.build(@sign * them.sign_bit, 0, 0, :infinity)
  end

  # The receiver with `digits` past the point, or as an Integer-valued
  # BigDecimal when the caller names none.
  def rounded(digits, mode)
    return self unless finite?
    return round_to(0, mode).to_int_value if digits.nil?

    round_to(digits, mode)
  end

  def round_to(digits, mode)
    drop = n_significant_digits - @exp - digits
    return self if drop <= 0

    kept = drop >= n_significant_digits ? carry_only(drop, mode) : apply_rounding(@digits, drop, mode, @sign)
    BigDecimal.send(:from_int, @sign, kept, @exp - drop + (kept.zero? ? 0 : kept.to_s.length - (n_significant_digits - drop)))
  end

  # Every digit falls away, so the answer is 0 or 1 in the last place
  # the caller kept.
  def carry_only(drop, mode)
    apply_rounding(@digits, drop, mode, @sign)
  end

  # `digits` with its last `drop` digits taken off, rounded the way
  # `mode` says. `sign` decides which way ceiling and floor go.
  def apply_rounding(digits, drop, mode, sign)
    return digits if drop <= 0

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

  def power(other)
    return power_int(other) if other.is_a?(Integer)

    BigDecimal(to_f**BigDecimal(other).to_f, 0)
  end

  def power_int(n)
    return BigDecimal(1) if n.zero?
    return BigDecimal(1) / power_int(-n) if n.negative?

    result = BigDecimal(1)
    base = self
    while n.positive?
      result *= base if n.odd?
      base *= base if n > 1
      n >>= 1
    end
    result
  end

  # Newton's method on the integer digits, which needs no division of
  # our own past Integer#/.
  def newton_sqrt(digits)
    shift = (2 * digits) - (@exp - n_significant_digits)
    shift += 1 if shift.odd?
    scaled = @digits * (10**shift)
    guess = Integer.sqrt(scaled)
    BigDecimal.send(:from_int, 1, guess, ((@exp - n_significant_digits + shift) / 2) + guess.to_s.length).round_significant(digits)
  end

  # `0.<digits>e<exp>` split into groups, or the plain form; `F` asks
  # for the plain one and a leading count asks for groups.
  Shape = Struct.new(:groups, :kind) do
    def initialize(format)
      text = format.to_s
      super(text[/\d+/].to_i, text[/[a-zA-Z+ ]/].to_s)
    end

    def plain? = kind.casecmp("f").zero?

    def lead(sign)
      return "-" if sign.negative?

      kind == "+" || kind == " " ? kind : ""
    end
  end
  private_constant :Shape

  def grouped(text, size)
    return text if size.zero?

    text.scan(/.{1,#{size}}/).join(" ")
  end

  def exponent_body(groups)
    return "0.0" if zero?

    "0.#{grouped(significant, groups)}e#{@exp}"
  end

  def plain_body(groups)
    return "0.0" if zero?

    text = significant
    if @exp <= 0
      "0.#{grouped(('0' * -@exp) + text, groups)}"
    elsif @exp >= text.length
      "#{grouped(text + ('0' * (@exp - text.length)), groups)}.0"
    else
      "#{grouped(text[0, @exp], groups)}.#{grouped(text[@exp..], groups)}"
    end
  end
end

BigDecimal.const_set(:INFINITY, BigDecimal.build(1, 0, 0, :infinity))
BigDecimal.const_set(:NAN, BigDecimal.build(1, 0, 0, :nan))

module Kernel
  # `BigDecimal(value)`: text is read as it is written, an Integer is
  # exact, and a Float needs a precision because its own digits stop.
  def BigDecimal(value, precision = 0, exception: true)
    case value
    when BigDecimal then value
    when Integer then BigDecimal.send(:from_digits, value.negative? ? -1 : 1, value.abs.to_s, value.abs.to_s.length)
    when Float then BigDecimal.send(:from_float, value, precision)
    when Rational then BigDecimal.send(:from_rational, value, precision)
    when String then BigDecimal.send(:interpret_strictly, value)
    when nil then raise TypeError, "can't convert nil into BigDecimal"
    else
      raise TypeError, "can't convert #{value.class} into BigDecimal" unless value.respond_to?(:to_str)

      BigDecimal(value.to_str, precision)
    end
  rescue ArgumentError, TypeError, FloatDomainError
    raise if exception

    nil
  end

  module_function :BigDecimal
  public :BigDecimal
end

class BigDecimal
  def self.interpret_strictly(source) = Parse.read(source, true)
  private_class_method :interpret_strictly

  # A Float has no more digits than its own round trip shows, so with
  # no precision asked for those are the digits the answer keeps.
  def self.from_float(value, precision)
    raise FloatDomainError, value.to_s if value.nan? || value.infinite?
    raise ArgumentError, "negative precision" if precision.negative?

    made = Parse.read(format("%.17e", value), false).round_significant(precision.zero? ? 17 : precision)
    precision.zero? ? Parse.read(value.to_s, false) : made
  end
  private_class_method :from_float

  def self.from_rational(value, precision)
    raise ArgumentError, "can't omit precision for a Rational" if precision.zero?

    BigDecimal(value.numerator).div(BigDecimal(value.denominator), precision)
  end
  private_class_method :from_rational
end
