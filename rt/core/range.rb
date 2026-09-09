# Range: a plain object holding its bounds, with everything else here.
class Range
  include Enumerable

  def initialize(low, high, exclude_end = false)
    @begin = low
    @end = high
    @excl = exclude_end ? true : false
  end

  def begin = @begin
  def end = @end
  def first(n = nil)
    return @begin if n.nil?

    out = []
    each do |v|
      break if out.size >= n

      out << v
    end
    out
  end

  def last(n = nil)
    return @end if n.nil?

    to_a.last(n)
  end

  def min(n = nil, &block)
    return to_a.min(n, &block) if n || block

    @excl && @begin == @end ? nil : first
  end

  def max(n = nil, &block)
    return to_a.max(n, &block) if n || block

    @excl ? (@end.is_a?(Integer) ? @end - 1 : raise(TypeError, "cannot exclude non Integer end value")) : @end
  end
  def exclude_end? = @excl

  def each
    return to_enum(:each) { size } unless block_given?

    v = @begin
    if v.is_a?(Integer)
      if @end.nil?
        while true
          yield v
          v += 1
        end
      end
      last = @excl ? @end - 1 : @end
      while v <= last
        yield v
        v += 1
      end
    elsif v.is_a?(String)
      return self if @end.is_a?(String) && v.length > @end.length

      while true
        break if @excl && v == @end

        yield v
        break if v == @end || (@end.is_a?(String) && v.length >= @end.length && v.succ.length > @end.length)

        v = v.succ
      end
    else
      raise TypeError, "can't iterate from #{v.class}"
    end
    self
  end

  def reverse_each(&block)
    to_a.reverse.each(&block)
    self
  end

  def size
    return nil unless @begin.is_a?(Integer)
    return Float::INFINITY if @end.nil?

    n = @end - @begin + (@excl ? 0 : 1)
    n < 0 ? 0 : n
  end

  def count(*args, &block)
    return size if args.empty? && !block

    super
  end

  def cover?(v)
    return false if @begin && (v <=> @begin).nil?
    return false if @begin && (v <=> @begin) < 0
    return true if @end.nil?

    c = v <=> @end
    return false if c.nil?

    @excl ? c < 0 : c <= 0
  end

  def include?(v) = cover?(v)
  def member?(v) = cover?(v)
  def ===(v) = cover?(v)

  def step(n = 1, &block)
    Primitive.zr_unimplemented("Range#step over non-Numerics") unless @begin.is_a?(Numeric) && (@end.nil? || @end.is_a?(Numeric)) && n.is_a?(Numeric)
    raise ArgumentError, "step can't be 0" if n.zero?

    seq = Enumerator::ArithmeticSequence.for(@begin, @end, n, @excl, self)
    return seq unless block

    seq.each(&block)
    self
  end
  alias % step

  def ==(other)
    other.is_a?(Range) && @begin == other.begin && @end == other.end && @excl == other.exclude_end?
  end

  # Whether some value lies in both ranges; an empty range overlaps
  # nothing.
  def overlap?(other)
    raise TypeError, "wrong argument type #{other.class} (expected Range)" unless other.is_a?(Range)
    return false if empty_range? || other.send(:empty_range?)

    !(before?(self, other) || before?(other, self))
  end

  def bsearch(&block)
    return to_enum(:bsearch) unless block
    return float_bsearch(&block) if @begin.is_a?(Float) || @end.is_a?(Float)
    raise TypeError, "can't do binary search for #{@begin.class}" unless (@begin.nil? || @begin.is_a?(Integer)) && (@end.nil? || @end.is_a?(Integer))

    low = @begin
    high = @end.nil? ? nil : (@excl ? @end - 1 : @end)
    Primitive.zr_unimplemented("Range#bsearch on a beginless range") if low.nil?
    if high.nil?
      span = 1
      span *= 2 until bsearch_hit?(yield(low + span))
      high = low + span
    end
    found = nil
    while low <= high
      mid = low + (high - low) / 2
      answer = yield(mid)
      case answer
      when true
        found = mid
        high = mid - 1
      when false, nil
        low = mid + 1
      when Numeric
        return mid if answer == 0

        answer < 0 ? high = mid - 1 : low = mid + 1
      else
        raise TypeError, "wrong argument type #{answer.class} (must be numeric, true, false or nil)"
      end
    end
    found
  end

  def eql?(other)
    other.is_a?(Range) && @begin.eql?(other.begin) && @end.eql?(other.end) && @excl == other.exclude_end?
  end

  def hash = [@begin, @end, @excl].hash

  private

  def empty_range?
    Primitive.attr! :hidden
    return false if @begin.nil? || @end.nil?

    c = @begin <=> @end
    c.nil? || c > 0 || (c == 0 && @excl)
  end

  # Whether every value of `a` comes before every value of `b`.
  def before?(a, b)
    Primitive.attr! :hidden
    return false if a.end.nil? || b.begin.nil?

    c = a.end <=> b.begin
    c < 0 || (c == 0 && a.exclude_end?)
  end

  def bsearch_hit?(answer)
    Primitive.attr! :hidden
    answer == true || (answer.is_a?(Numeric) && answer <= 0)
  end

  # Bisection by value until the two ends are adjacent doubles, which
  # lands on the same double a search over the bit order finds.
  def float_bsearch
    Primitive.attr! :hidden
    Primitive.zr_unimplemented("Range#bsearch over Floats with an open end") if @begin.nil? || @end.nil?

    low = @begin.to_f
    high = @end.to_f
    found = nil
    return nil if low > high || (@excl && low == high)

    high = high.prev_float if @excl
    while low <= high
      mid = low + (high - low) / 2
      answer = yield(mid)
      case answer
      when true
        found = mid
        break if mid == low

        high = mid.prev_float
      when false, nil
        break if mid == high

        low = mid.next_float
      when Numeric
        return mid if answer == 0

        if answer < 0
          break if mid == low

          high = mid.prev_float
        else
          break if mid == high

          low = mid.next_float
        end
      else
        raise TypeError, "wrong argument type #{answer.class} (must be numeric, true, false or nil)"
      end
    end
    found
  end

  public

  def to_s = "#{@begin}#{@excl ? "..." : ".."}#{@end}"

  # An endless or beginless range leaves that side blank; only a range
  # with neither end spells its nils.
  def inspect
    dots = @excl ? "..." : ".."
    return "nil#{dots}nil" if @begin.nil? && @end.nil?

    "#{@begin.inspect unless @begin.nil?}#{dots}#{@end.inspect unless @end.nil?}"
  end
  def sum = inject(0) { |a, b| a + b }
end
