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

  def min = @excl && @begin == @end ? nil : first
  def max = @excl ? (@end.is_a?(Integer) ? @end - 1 : raise(TypeError, "cannot exclude non Integer end value")) : @end
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
    Primitive.zr_unimplemented("Range#step over non-Integers") unless @begin.is_a?(Integer) && (@end.nil? || @end.is_a?(Integer)) && n.is_a?(Integer)
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

  def eql?(other)
    other.is_a?(Range) && @begin.eql?(other.begin) && @end.eql?(other.end) && @excl == other.exclude_end?
  end

  def hash = [@begin, @end, @excl].hash

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
