# frozen_string_literal: true

# Range: a plain object holding its bounds, with everything else here.
class Range
  include Enumerable

  # A plain Range is frozen from birth; a subclass's instance is not.
  def initialize(low, high, exclude_end = false)
    modify!
    raise ArgumentError, +"bad value for range" if !low.nil? && !high.nil? && (low <=> high).nil?

    bound(low, high, exclude_end ? true : false)
    freeze if instance_of?(Range)
  end

  def begin = @begin
  def end = @end

  # CRuby counts the arguments itself, and says it wants one.
  def first(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1)" if args.size > 1
    raise RangeError, +"cannot get the first element of beginless range" if @begin.nil?
    return @begin if args.empty?

    n = Primitive.zr_index_operand_m(args[0])
    raise ArgumentError, +"negative array size (or size too big)" if n < 0

    out = []
    return out if n == 0

    each do |v|
      out << v
      break if out.size >= n
    end
    out
  end

  def last(n = nil)
    raise RangeError, +"cannot get the last element of endless range" if @end.nil?
    return @end if n.nil?

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"negative array size" if n < 0

    to_a.last(n)
  end

  def min(n = nil, &block)
    raise RangeError, +"cannot get the minimum of beginless range" if @begin.nil?
    if block
      raise RangeError, +"cannot get the minimum of endless range with custom comparison method" if @end.nil?

      return super
    end
    return first(n) unless n.nil?

    c = @end.nil? ? -1 : (@begin <=> @end)
    c.nil? || c > 0 || (c == 0 && @excl) ? nil : @begin
  end

  def max(n = nil, &block)
    raise RangeError, +"cannot get the maximum of endless range" if @end.nil?
    if block || n || (@excl && !@end.is_a?(Numeric))
      if @begin.nil?
        raise RangeError, +"cannot get the maximum of beginless range with custom comparison method" if block
        raise TypeError, +"can't iterate from NilClass" unless @end.is_a?(Integer)

        return counted_down(n)
      end
      raise ArgumentError, +"negative array size (or size too big)" if n && n < 0

      return super
    end

    c = @begin.nil? ? -1 : (@begin <=> @end)
    return nil if c.nil? || c > 0
    if @excl
      raise TypeError, +"cannot exclude non Integer end value" unless @end.is_a?(Integer)
      return nil if c == 0
      raise TypeError, +"cannot exclude end value with non Integer begin value" unless @begin.nil? || @begin.is_a?(Integer)

      return @end - 1
    end
    @end
  end

  def minmax(&block)
    return super if block

    [min, max]
  end

  # `n` values down from an Integer end, for a beginless range.
  def counted_down(n)
    Primitive.attr! :hidden
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"negative array size (or size too big)" if n < 0

    top = @excl ? @end - 1 : @end
    Array.new(n) { |i| top - i }
  end

  def exclude_end? = @excl

  def each
    return to_enum(:each) { size } unless block_given?

    v = @begin
    if v.is_a?(Integer) && (@end.nil? || @end.is_a?(Integer))
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
    elsif v.is_a?(Symbol) && (@end.nil? || @end.is_a?(Symbol))
      Range.new(v.to_s, @end&.to_s, @excl).each { |s| yield s.to_sym }
    elsif (text = String.try_convert(v))
      if @end.nil?
        while true
          yield text
          text = text.succ
        end
      end
      text.upto(@end, @excl) { |s| yield s }
    else
      # range_each_func: any object that responds to succ walks toward the
      # end while <=> says it has not passed it.
      raise TypeError, "can't iterate from #{v.class}" unless v.respond_to?(:succ)

      if @end.nil?
        while true
          yield v
          v = v.succ
        end
      end
      if @excl
        while range_less(v, @end) < 0
          yield v
          v = v.succ
        end
      else
        while (c = range_less(v, @end)) <= 0
          yield v
          break if c == 0

          v = v.succ
        end
      end
    end
    self
  end

  # r_less: `a <=> b` as rb_cmpint reads it, and past the end when the
  # two do not compare.
  def range_less(a, b)
    Primitive.attr! :hidden
    c = a <=> b
    return 1 if c.nil?
    return c <=> 0 if c.is_a?(Integer)

    c > 0 ? 1 : (c < 0 ? -1 : 0)
  end

  # Integer ends count down without an Array, which a beginless range
  # needs; anything else walks the Array.
  def reverse_each(&block)
    return to_enum(:reverse_each) { size } unless block
    raise TypeError, "can't iterate from #{@end.class}" if @end.nil?
    # Only an Integer end counts down, so a beginless range with any
    # other end walks from its begin, which is nil.
    raise TypeError, "can't iterate from #{@begin.class}" if @begin.nil? && !@end.is_a?(Integer)

    if @end.is_a?(Integer) && (@begin.nil? || @begin.is_a?(Integer))
      v = @excl ? @end - 1 : @end
      while @begin.nil? || v >= @begin
        yield v
        v -= 1
      end
      return self
    end

    to_a.reverse.each(&block)
    self
  end

  def to_a
    raise RangeError, +"cannot convert endless range to an array" if @end.nil?
    if Primitive.zr_fixnum_p_m(@begin) && Primitive.zr_fixnum_p_m(@end) && Primitive.zr_basic_method_m(self, :each)
      return Primitive.zr_fixnum_range_ary(@begin, @end, @excl)
    end

    super
  end
  alias entries to_a

  def to_set(...)
    raise RangeError, +"cannot convert endless range to a set" if @end.nil?

    super
  end

  # Counted only from an Integer: a Float or nil start cannot iterate,
  # any other start has no size.
  # range_size: a count only from an Integer to a number or to no end.
  # Any other range has none, and one whose begin has no `succ` cannot
  # be counted at all.
  def size
    unless @begin.is_a?(Integer) && (@end.nil? || @end.is_a?(Numeric))
      raise TypeError, "can't iterate from #{@begin.class}" unless @begin.respond_to?(:succ)

      return nil
    end
    return Float::INFINITY if @end.nil?

    n = if @end.is_a?(Float)
          return Float::INFINITY if @end.infinite? && @end > 0

          Enumerator::ArithmeticSequence.for(self, :step, [], {}, @begin, @end, 1, @excl).size
        else
          delta = @end - @begin
          whole = delta.floor
          @excl && whole == delta ? whole : whole + 1
        end
    n < 0 ? 0 : n
  end

  # A range with an open side has an infinite count, which CRuby
  # returns without a walk. An argument or a block counts the members
  # that match, so those walk as Enumerable does.
  def count(*args, &block)
    return super unless args.empty? && !block
    return Float::INFINITY if @begin.nil? || @end.nil?
    return size if @begin.is_a?(Integer)

    super
  end

  # A Range argument is covered as a whole; `===`, include? and
  # member? compare a Range like any other value.
  def cover?(v)
    return covers_range?(v) if v.is_a?(Range)

    covers_value?(v)
  end

  # r_cover_p: `begin <=> v`, then `v <=> end`, each sent once.
  def covers_value?(v)
    Primitive.attr! :hidden
    return false unless @begin.nil? || Range.send(:r_less, @begin, v) <= 0

    @end.nil? || Range.send(:r_less, v, @end) <= (@excl ? -1 : 0)
  end

  # r_less: `a <=> b` as rb_cmpint reads it, with nil above everything.
  def self.r_less(a, b)
    Primitive.attr! :hidden
    c = a <=> b
    c.nil? ? 2_147_483_647 : Primitive.zr_cmpint(c, a, b)
  end
  private_class_method :r_less

  # A String range covers single characters by order and walks the rest.
  def include?(v)
    return covers_value?(v) unless @begin.is_a?(String) || @end.is_a?(String)
    return covers_value?(v) if v.is_a?(String) && v.size == 1 && (@begin.nil? || @begin.size == 1) && (@end.nil? || @end.size == 1)
    return false unless v.is_a?(String)

    each { |x| return true if x == v }
    false
  end
  alias member? include?
  def ===(v) = covers_value?(v)

  def step(*args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

    stride(args, :step, &block)
  end

  def %(n, &block) = stride([n], :%, &block)

  # range_step, which `%` shares: a numeric range with a numeric step
  # and no block is an ArithmeticSequence, a beginless one among them;
  # every other walk adds the step to each value in turn.
  def stride(args, name, &block)
    Primitive.attr! :hidden
    textual = @begin.is_a?(String) || @begin.is_a?(Symbol)
    if args.empty? && !(@begin.is_a?(Numeric) || textual || (@begin.nil? && @end.is_a?(Numeric)))
      raise ArgumentError, +"step is required for non-numeric ranges"
    end

    n = args.empty? ? 1 : args[0]
    numeric = n.is_a?(Numeric)
    raise ArgumentError, +"step can't be 0" if numeric && @begin.is_a?(Numeric) && Primitive.zr_rb_equal(n, 0)

    sequence = numeric && ((@begin.is_a?(Numeric) && (@end.nil? || @end.is_a?(Numeric))) || (@begin.nil? && @end.is_a?(Numeric)))
    return Enumerator::ArithmeticSequence.for(self, name, args, {}, @begin, @end, n, @excl) if sequence && !block
    return stepped(n, name, &block) if textual || (@begin.nil? && (@end.is_a?(String) || @end.is_a?(Symbol)))
    raise ArgumentError, +"#step for non-numeric beginless ranges is meaningless" if @begin.nil? && !block
    raise ArgumentError, +"#step iteration for beginless ranges is meaningless" if @begin.nil?
    return added(n, name, &block) unless sequence
    return fixnum_step(n, &block) if Primitive.zr_fixnum_p_m(@begin) && Primitive.zr_fixnum_p_m(n) && (@end.nil? || Primitive.zr_fixnum_p_m(@end))

    Enumerator::ArithmeticSequence.for(self, name, args, {}, @begin, @end, n, @excl).each(&block)
    self
  end

  # range_step's fixnum walk, which adds and compares in C.
  def fixnum_step(unit)
    Primitive.attr! :hidden
    i = @begin
    if @end.nil?
      while true
        yield i
        i += unit
      end
    end
    if unit < 0
      last = @excl ? @end : @end - 1
      while i > last
        yield i
        i += unit
      end
    else
      last = @excl ? @end : @end + 1
      while i < last
        yield i
        i += unit
      end
    end
    self
  end

  # A step of any kind: each value is the last plus the step, until
  # the end.
  def added(n, name)
    Primitive.attr! :hidden
    return to_enum(name, n) unless block_given?
    raise ArgumentError, +"#step iteration for beginless ranges is meaningless" if @begin.nil?

    v = @begin
    while @end.nil? || (@excl ? v < @end : v <= @end)
      yield v
      v += n
    end
    self
  end
  # Every `n`th element of a String range, by succ; the argument checks
  # wait for the walk.
  def stepped(n, name, &block)
    Primitive.attr! :hidden
    return added(n, name, &block) unless n.is_a?(Integer)
    return to_enum(name, n) unless block
    raise ArgumentError, +"step can't be negative" if n < 0
    raise ArgumentError, +"step can't be 0" if n == 0

    i = 0
    each do |v|
      yield v if i % n == 0
      i += 1
    end
    self
  end

  def ==(other)
    other.is_a?(Range) && @begin == other.begin && @end == other.end && @excl == other.exclude_end?
  end

  # Whether some value lies in both ranges; an empty range overlaps
  # nothing.
  # range_overlap, over both ranges' own bounds: a subclass's begin and
  # end are not called.
  def overlap?(other)
    raise TypeError, "wrong argument type #{conversion_name(other)} (expected Range)" unless other.is_a?(Range)

    other_begin, other_end, other_excl = other.send(:bounds)
    return false if empty_region?(@begin, other_end, other_excl)
    return false if empty_region?(other_begin, @end, @excl)

    if !@begin.nil? && !other_begin.nil?
      c = @begin <=> other_begin
      return false if c.nil?
      return true if c.is_a?(Integer) ? c.zero? : !(c > 0) && !(c < 0)
    elsif @begin.nil? && !@end.nil? && other_begin.nil? && !other_end.nil?
      return !(@end <=> other_end).nil?
    end
    return false if empty_region?(@begin, @end, @excl)

    !empty_region?(other_begin, other_end, other_excl)
  end

  def bsearch(&block)
    return to_enum(:bsearch) unless block
    return float_bsearch(&block) if @begin.is_a?(Float) || @end.is_a?(Float)
    raise TypeError, "can't do binary search for #{@begin.class}" unless (@begin.nil? || @begin.is_a?(Integer)) && (@end.nil? || @end.is_a?(Integer))

    low = @begin
    high = @end.nil? ? nil : (@excl ? @end - 1 : @end)
    if high.nil?
      span = 1
      span *= 2 until bsearch_hit?(yield(low + span))
      high = low + span
    elsif low.nil?
      span = 1
      span *= 2 while bsearch_hit?(yield(high - span))
      low = high - span
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

  # CRuby's r_cover_range_p: `v` must start inside and end no later,
  # an exclusive end short of an inclusive one by at least one value.
  def covers_range?(v)
    Primitive.attr! :hidden
    return false if !@end.nil? && v.end.nil?
    return false if !@begin.nil? && v.begin.nil?
    return false if !v.begin.nil? && !v.end.nil? && ordered(v.begin, v.end) > (v.exclude_end? ? -1 : 0)
    return false if !v.begin.nil? && !cover?(v.begin)

    cmp_end = @end.nil? ? 1 : ordered(@end, v.end)
    return cmp_end >= 0 if @excl == v.exclude_end?
    return cmp_end > 0 if @excl
    return true if cmp_end >= 0

    v_max = begin
      v.max
    rescue TypeError
      nil
    end
    return false if v_max.nil?

    ordered(@end, v_max) >= 0
  end

  # `a <=> b` as an Integer; incomparable counts as far greater.
  def ordered(a, b)
    Primitive.attr! :hidden
    c = a <=> b
    c.nil? ? 2**31 : c
  end

  def bounds
    Primitive.attr! :hidden
    [@begin, @end, @excl]
  end

  # empty_region_p: no value lies from `low` to `high`.
  def empty_region?(low, high, excl)
    Primitive.attr! :hidden
    return false if low.nil? || high.nil?

    less = range_less(low, high)
    less > 0 || (excl && less == 0)
  end

  def bsearch_hit?(answer)
    Primitive.attr! :hidden
    answer == true || (answer.is_a?(Numeric) && answer <= 0)
  end

  # Bisection over the order the double bits give, so each step halves
  # the doubles left, not the span. An open end is an infinity.
  def float_bsearch
    Primitive.attr! :hidden
    first = @begin.nil? ? -Float::INFINITY : @begin.to_f
    last = @end.nil? ? Float::INFINITY : @end.to_f
    return nil if first > last || (@excl && first == last)

    low = float_order(first)
    high = float_order(last) - (@excl ? 1 : 0)
    found = nil
    while low <= high
      mid = low + (high - low) / 2
      answer = yield(float_of_order(mid))
      case answer
      when true
        found = mid
        high = mid - 1
      when false, nil
        low = mid + 1
      when Numeric
        return float_of_order(mid) if answer == 0

        answer < 0 ? high = mid - 1 : low = mid + 1
      else
        raise TypeError, "wrong argument type #{answer.class} (must be numeric, true, false or nil)"
      end
    end
    found.nil? ? nil : float_of_order(found)
  end

  # Doubles in ascending order as integers: the bits of a positive one,
  # the bits of a negative one mirrored below zero.
  def float_order(f)
    Primitive.attr! :hidden
    low, high = Primitive.zr_float_halves(f)
    bits = (high << 32) | low
    bits < (1 << 63) ? bits : -(bits - (1 << 63))
  end

  def float_of_order(n)
    Primitive.attr! :hidden
    bits = n >= 0 ? n : (1 << 63) - n
    Primitive.zr_float_of_halves(bits & 0xffff_ffff, bits >> 32)
  end

  public

  # Each end as rb_obj_as_string writes it, joined in the encoding of
  # the beginning's text.
  def to_s = Primitive.zr_obj_as_string(@begin).dup << dots << Primitive.zr_obj_as_string(@end)

  # An endless or beginless range leaves that side blank; only a range
  # with neither end spells its nils. A blank beginning is an empty
  # binary String, as inspect_range starts one.
  def inspect
    text = @begin.nil? && !@end.nil? ? String.new : Primitive.zr_inspect(@begin).dup
    text << dots
    text << Primitive.zr_inspect(@end) unless @end.nil? && !@begin.nil?
    text
  end

  private

  def dots
    Primitive.attr! :hidden
    @excl ? +"..." : +".."
  end

  # What `dup` and `clone` fill a copy with: the other Range's bounds.
  def initialize_copy(other)
    modify!
    raise TypeError, +"initialize_copy should take same class object" unless other.instance_of?(self.class)

    bound(other.begin, other.end, other.exclude_end?)
    self
  end

  # rb_range_modify: a Range is set once, and a frozen one never.
  def modify!
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if frozen?
    raise NameError.new(+"'initialize' called twice", :initialize, receiver: self) if Primitive.zr_hidden_get(self, :__built__)
  end

  def bound(low, high, exclude_end)
    Primitive.attr! :hidden
    @begin = low
    @end = high
    @excl = exclude_end
    Primitive.zr_hidden_set(self, :__built__, true)
  end
end
