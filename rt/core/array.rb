# Array over the kernel's storage. CRuby writes these in C, so none
# goes through `each`: a backtrace must not show a row for it.
class Array
  include Enumerable

  # rb_ary_find: the first element the block accepts, else what
  # `ifnone` answers.
  def find(ifnone = (omitted = true; nil))
    return to_enum(__callee__, *([ifnone] unless omitted)) unless block_given?

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      element = Primitive.zr_ary_aref1_m(self, i)
      return element if yield(element)

      i += 1
    end
    ifnone&.call
  end
  alias detect find

  # The last element the block accepts, else what `ifnone` answers.
  def rfind(ifnone = (omitted = true; nil))
    return to_enum(:rfind, *([ifnone] unless omitted)) unless block_given?

    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      element = Primitive.zr_ary_aref1_m(self, i)
      return element if yield(element)

      i -= 1
    end
    ifnone&.call
  end

  # rb_ary_any_p and its kin: how many elements meet the criterion, a
  # pattern's `===`, the block, or truthiness, counted no further than
  # `enough` asks.
  def any?(*pattern, &block) = meeting(pattern, block, 1).positive?
  def all?(*pattern, &block) = meeting(pattern, block, 1, negate: true).zero?
  def none?(*pattern, &block) = meeting(pattern, block, 1).zero?
  def one?(*pattern, &block) = meeting(pattern, block, 2) == 1

  def take_while
    return to_enum(:take_while) unless block_given?

    i = 0
    i += 1 while i < Primitive.zr_ary_len_m(self) && yield(Primitive.zr_ary_aref1_m(self, i))
    Primitive.zr_ary_aref2_m(self, 0, i)
  end

  def drop_while
    return to_enum(:drop_while) unless block_given?

    i = 0
    i += 1 while i < Primitive.zr_ary_len_m(self) && yield(Primitive.zr_ary_aref1_m(self, i))
    Primitive.zr_ary_aref2_m(self, i, Primitive.zr_ary_len_m(self))
  end

  def reverse = reversed

  # rb_ary_reverse's copy, which reverse! makes as a function.
  def reversed
    Primitive.attr! :hidden
    out = []
    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      out << Primitive.zr_ary_aref1_m(self, i)
      i -= 1
    end
    out
  end

  def last(n = (none = true))
    Primitive.attr! :ruby
    return Primitive.zr_ary_aref1_m(self, -1) if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    from = Primitive.zr_ary_len_m(self) - n
    from = 0 if from < 0
    out = []
    while from < Primitive.zr_ary_len_m(self)
      out << Primitive.zr_ary_aref1_m(self, from)
      from += 1
    end
    out
  end

  def first(n = (none = true))
    Primitive.attr! :ruby
    return Primitive.zr_ary_aref1_m(self, 0) if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    out = []
    i = 0
    while i < n && i < Primitive.zr_ary_len_m(self)
      out << Primitive.zr_ary_aref1_m(self, i)
      i += 1
    end
    out
  end

  # A comparison already in flight on this Array compares as equal.
  def <=>(other)
    return nil unless other.is_a?(Array)
    return 0 if equal?(other)
    return 0 if Primitive.zr_recursive_enter(self, :<=>)

    begin
      i = 0
      while i < Primitive.zr_ary_len_m(self) && i < other.size
        c = Primitive.zr_ary_aref1_m(self, i) <=> other[i]
        return c if c != 0

        i += 1
      end
      Primitive.zr_ary_len_m(self) <=> other.size
    ensure
      Primitive.zr_recursive_leave(self, :<=>)
    end
  end

  def +(other)
    other = Array.try_convert(other) || raise(TypeError, "no implicit conversion of #{conversion_name(other)} into Array")
    out = Array.new(self)
    i = 0
    while i < other.size
      out << other[i]
      i += 1
    end
    out
  end

  def at(index) = Primitive.zr_ary_aref1_m(self, Primitive.zr_index_operand_m(index))

  # rb_ary_join: the text starts empty in US-ASCII, and the first
  # element's text gives it its encoding -- unless that element is an
  # Array, whose own elements join the text as the rest do.
  def join(sep = nil)
    sep = $, if sep.nil?
    return String.new(encoding: Encoding::US_ASCII) if (Primitive.zr_ary_len_m(self) == 0)

    sep = sep.nil? ? "" : Primitive.zr_str_operand(sep)
    raise ArgumentError, "recursive array join" if Primitive.zr_recursive_enter(self, :join)

    begin
      s = String.new(encoding: Encoding::US_ASCII)
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        s << sep if i > 0
        part = join_part(Primitive.zr_ary_aref1_m(self, i))
        if part.is_a?(Array)
          s << part.join(sep)
        else
          s << part
          s.force_encoding(part.encoding) if i.zero?
        end
        i += 1
      end
      s
    ensure
      Primitive.zr_recursive_leave(self, :join)
    end
  end

  # What one element stands for in `join`: its text, or an Array whose
  # elements join in its place.
  def join_part(x)
    Primitive.attr! :hidden
    return x if x.is_a?(String) || x.is_a?(Array)
    return x.to_str if x.respond_to?(:to_str)
    return x.to_ary if x.respond_to?(:to_ary)

    Primitive.zr_obj_as_string(x)
  end

  def compact
    out = []
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      out << Primitive.zr_ary_aref1_m(self, i) unless Primitive.zr_ary_aref1_m(self, i).nil?
      i += 1
    end
    out
  end

  def index(v = nil)
    return to_enum(:index) if v.nil? && !block_given?

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return i if block_given? ? yield(x) : Primitive.zr_rb_equal(x, v)

      i += 1
    end
    nil
  end

  # Floats add with Kahan-Babuska compensation, as CRuby's sum does,
  # from the first Float met while the sum is still a Float.
  def sum(init = 0)
    acc = init
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = block_given? ? yield(Primitive.zr_ary_aref1_m(self, i)) : Primitive.zr_ary_aref1_m(self, i)
      if acc.is_a?(Float) || (x.is_a?(Float) && (acc.is_a?(Integer) || acc.is_a?(Rational)))
        return float_sum(acc.to_f, x, i + 1) { |j| block_given? ? yield(Primitive.zr_ary_aref1_m(self, j)) : Primitive.zr_ary_aref1_m(self, j) }
      end
      acc += x
      i += 1
    end
    acc
  end

  def min(n = nil, &block)
    return nmin_run(n, false, false, block, true) unless n.nil?

    best = nil
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      best = Primitive.zr_ary_aref1_m(self, i) if i == 0 || compared(Primitive.zr_ary_aref1_m(self, i), best, block) < 0
      i += 1
    end
    best
  end

  def max(n = nil, &block)
    return nmin_run(n, false, true, block, true) unless n.nil?

    best = nil
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      best = Primitive.zr_ary_aref1_m(self, i) if i == 0 || compared(Primitive.zr_ary_aref1_m(self, i), best, block) > 0
      i += 1
    end
    best
  end

  # `a <=> b`, or the block's answer, as an Integer; nil fails as
  # ruby's comparison does.
  def compared(a, b, block = nil)
    Primitive.attr! :hidden
    c = block ? block.call(a, b) : (a <=> b)
    Primitive.zr_cmperr(a, b) if c.nil?

    c
  end

  def rotate!(n = 1)
    n = Primitive.zr_index_operand_m(n)
    replaced(rotated(n))
  end

  def rassoc(value)
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      row = Primitive.zr_ary_aref1_m(self, i)
      return row if row.is_a?(Array) && row.size > 1 && Primitive.zr_rb_equal(row[1], value)

      i += 1
    end
    nil
  end

  def bsearch(&block)
    return to_enum(:bsearch) unless block

    at = searched(&block)
    at && Primitive.zr_ary_aref1_m(self, at)
  end

  # Binary search in find-minimum mode (the block answers true or
  # false) or find-any mode (the block answers a number's sign).
  def bsearch_index(&block)
    return to_enum(:bsearch_index) unless block

    searched(&block)
  end

  # rb_ary_bsearch_index, which bsearch calls as a function.
  def searched
    Primitive.attr! :hidden
    low = 0
    high = Primitive.zr_ary_len_m(self)
    found = nil
    while low < high
      mid = low + (high - low) / 2
      answer = yield(Primitive.zr_ary_aref1_m(self, mid))
      case answer
      when true
        found = mid
        high = mid
      when false, nil
        low = mid + 1
      when Numeric
        return mid if answer == 0

        sign = answer <=> 0
        raise ArgumentError, "comparison of #{answer.class} with 0 failed" if sign.nil?

        sign < 0 ? high = mid : low = mid + 1
      else
        raise TypeError, "wrong argument type #{answer.class} (must be numeric, true, false or nil)"
      end
    end
    found
  end

  # The forms of many operands start from a plain copy, as the C starts
  # from rb_ary_dup, so the receiver's own operators are not called.
  def intersection(*others) = others.inject(Array.new(self)) { |acc, other| acc & other }

  def union(*others) = others.inject(unique) { |acc, other| acc | other }

  def difference(*others) = others.inject(Array.new(self)) { |acc, other| acc - other }

  def intersect?(other) = !(Array.new(self) & other).empty?

  def repeated_combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:repeated_combination, k) { k < 0 ? 0 : (k == 0 ? 1 : (Primitive.zr_ary_len_m(self) + k - 1).downto(Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b } / (1..k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && !(Primitive.zr_ary_len_m(self) == 0)
      pick_repeated(k, 0, []) { |c| yield c }
    end
    self
  end

  def repeated_permutation(k)
    # Without a block the count is not read, so a bad one raises only
    # where the enumerator runs.
    unless block_given?
      return to_enum(:repeated_permutation, k) do
        n = Primitive.zr_index_operand_m(k)
        n.negative? ? 0 : Primitive.zr_ary_len_m(self)**n
      end
    end

    k = Primitive.zr_index_operand_m(k)
    if k == 0
      yield []
    elsif k > 0 && !(Primitive.zr_ary_len_m(self) == 0)
      place_repeated(k, []) { |c| yield c }
    end
    self
  end

  def combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:combination, k) { k < 0 || k > Primitive.zr_ary_len_m(self) ? 0 : (1..Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b } / ((1..k).inject(1) { |a, b| a * b } * (1..Primitive.zr_ary_len_m(self) - k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && k <= Primitive.zr_ary_len_m(self)
      combine(k, 0, []) { |c| yield c }
    end
    self
  end

  def permutation(k = Primitive.zr_ary_len_m(self))
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:permutation, k) { k < 0 || k > Primitive.zr_ary_len_m(self) ? 0 : (Primitive.zr_ary_len_m(self) - k + 1..Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b } } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && k <= Primitive.zr_ary_len_m(self)
      permute(k, [], Array.new(Primitive.zr_ary_len_m(self), false)) { |c| yield c }
    end
    self
  end

  def take(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

    Primitive.zr_ary_aref2_m(self, 0, n)
  end

  def drop(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

    out = []
    i = n
    while i < Primitive.zr_ary_len_m(self)
      out << Primitive.zr_ary_aref1_m(self, i)
      i += 1
    end
    out
  end

  def deconstruct = self

  def slice(*args)
    case args.size
    when 1 then Primitive.zr_ary_aref1_m(self, args[0])
    when 2 then Primitive.zr_ary_aref2_m(self, args[0], args[1])
    else raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)"
    end
  end

  # `Array[1, 2]` is the constructor spelling of `[1, 2]`. A subclass
  # takes its own instance, which is what `Array[...].class` answers.
  def self.[](*args)
    return args if self == Array

    new.replace(args)
  end

  def self.try_convert(object)
    return object if object.is_a?(Array)
    return nil unless object.respond_to?(:to_ary)

    converted = object.to_ary
    raise TypeError, "can't convert #{conversion_name(object)} to Array (#{conversion_name(object)}#to_ary gives #{conversion_name(converted)})" unless converted.nil? || converted.is_a?(Array)

    converted
  end

  def to_ary = self

  # Membership here is by `hash` and `eql?`, as CRuby's set
  # operations decide it.
  def uniq(&block) = unique(&block)

  # rb_ary_uniq, which uniq!, union and & call as a function.
  def unique
    Primitive.attr! :hidden
    return Array.new(self) if Primitive.zr_ary_len_m(self) <= 1 && !block_given?

    seen = {}
    out = []
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      key = block_given? ? yield(x) : x
      unless seen.key?(key)
        seen[key] = true
        out << x
      end
      i += 1
    end
    out
  end

  # The same object counts as found before == is asked, so NaN finds
  # itself.
  def include?(v)
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return true if Primitive.zr_rb_equal(x, v)

      i += 1
    end
    false
  end

  def eql?(other)
    return false unless other.is_a?(Array) && Primitive.zr_ary_len_m(self) == other.size
    return true if equal?(other) || Primitive.zr_recursive_enter(self, :eql?)

    begin
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        return false unless Primitive.zr_ary_aref1_m(self, i).eql?(other[i])

        i += 1
      end
      true
    ensure
      Primitive.zr_recursive_leave(self, :eql?)
    end
  end

  def hash
    mask = 72057594037927935
    return 7 if Primitive.zr_recursive_enter(self, :hash)

    begin
      h = 7
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        h = (h * 31 + (Primitive.zr_ary_aref1_m(self, i).hash & mask)) & mask
        i += 1
      end
      h
    ensure
      Primitive.zr_recursive_leave(self, :hash)
    end
  end

  # A subclass answers a plain Array.
  def to_a = instance_of?(Array) ? self : Array.new(self)
  # Over the elements themselves, as rb_ary_count walks them: never
  # through `each`, with the length read again each time round.
  def count(item = (none = true), &block)
    return Primitive.zr_ary_len_m(self) if none && !block

    n = 0
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_at_m(self, i)
      n += 1 if none ? yield(x) : Primitive.zr_rb_equal(x, item)
      i += 1
    end
    n
  end

  # `pop(n)` takes the last n.
  def pop(n = (none = true))
    return Primitive.zr_ary_pop_m(self) if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0
    Primitive.zr_frozen_error(self) if frozen?

    count = Primitive.zr_ary_len_m(self)
    from = n > count ? 0 : count - n
    out = Primitive.zr_ary_aref2_m(self, from, count - from)
    Primitive.zr_ary_splice(self, from, out.size, [])
    out
  end

  def shift(n = (none = true))
    if none
      return nil if (Primitive.zr_ary_len_m(self) == 0)

      first = Primitive.zr_ary_aref1_m(self, 0)
      Primitive.zr_ary_splice(self, 0, 1, [])
      return first
    end
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    out = Primitive.zr_ary_aref2_m(self, 0, n)
    Primitive.zr_ary_splice(self, 0, out.size, [])
    out
  end

  def unshift(*vals)
    Primitive.zr_ary_splice(self, 0, 0, vals)
  end

  def prepend(*vals) = Primitive.zr_ary_splice(self, 0, 0, vals)

  def append(*vals) = Primitive.zr_ary_splice(self, Primitive.zr_ary_len_m(self), 0, vals)

  # A frozen receiver refuses before the index is read, and an index
  # below `-size - 1` names no place to insert at.
  def insert(index, *vals)
    Primitive.zr_frozen_error(self) if frozen?
    index = Primitive.zr_index_operand_m(index)
    return self if vals.empty?

    if index.negative?
      raise IndexError, "index #{index} too small for array; minimum: #{-Primitive.zr_ary_len_m(self) - 1}" if index < -Primitive.zr_ary_len_m(self) - 1

      index += Primitive.zr_ary_len_m(self) + 1
    end
    # rb_ary_splice's own bound, met before any element moves.
    raise IndexError, "index #{index} too big" if index > Primitive.zr_ary_len_m(self) && index > Primitive.zr_ary_max_size - vals.size

    Primitive.zr_ary_splice(self, index, 0, vals)
  end

  # The arguments are read before any is appended, so `a.concat(a, a)`
  # triples it.
  def concat(*others)
    Primitive.zr_frozen_error(self) if frozen?
    pieces = others.map do |o|
      ary = Array.try_convert(o) || raise(TypeError, "no implicit conversion of #{conversion_name(o)} into Array")
      ary.equal?(self) ? ary.dup : ary
    end
    pieces.each { |o| Primitive.zr_ary_splice(self, Primitive.zr_ary_len_m(self), 0, o) }
    self
  end

  def delete_at(index) = deleted_at(Primitive.zr_index_operand_m(index))

  # rb_ary_delete_at, which slice! calls as a function.
  def deleted_at(index)
    Primitive.attr! :hidden
    index += Primitive.zr_ary_len_m(self) if index < 0
    return nil if index < 0 || index >= Primitive.zr_ary_len_m(self)

    v = Primitive.zr_ary_aref1_m(self, index)
    Primitive.zr_ary_splice(self, index, 1, [])
    v
  end

  def delete(v)
    found = nil
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      if Primitive.zr_rb_equal(Primitive.zr_ary_aref1_m(self, i), v)
        found = Primitive.zr_ary_aref1_m(self, i)
        Primitive.zr_ary_splice(self, i, 1, [])
      else
        i += 1
      end
    end
    found.nil? && block_given? ? yield(v) : found
  end

  def delete_if
    return to_enum(:delete_if) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| !yield(x) }
    self
  end

  def reject!
    return to_enum(:reject!) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| !yield(x) } ? self : nil
  end

  def select!
    return to_enum(:select!) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| yield(x) } ? self : nil
  end

  def keep_if
    return to_enum(:keep_if) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| yield(x) }
    self
  end

  def filter!
    return to_enum(:filter!) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| yield(x) } ? self : nil
  end

  def clear = Primitive.zr_ary_clear(self, nil)

  def replace(other)
    array = Array.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Array"
    replaced(array)
  end

  # rb_ary_replace with an Array in hand.
  def replaced(array)
    Primitive.attr! :hidden
    Primitive.zr_ary_splice(self, 0, Primitive.zr_ary_len_m(self), array)
  end

  # `a[i] = v`, `a[start, len] = v` and `a[range] = v`: the span's
  # elements leave and the value's elements, or the value, take their
  # place.
  def []=(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)" unless args.size.between?(2, 3)

    Primitive.zr_frozen_error(self) if frozen?
    case args.size
    when 2
      index, value = args
      return Primitive.zr_ary_aset_at(self, index, value) unless index.is_a?(Range)

      start, len = range_span(index)
    when 3
      start, len, value = args
      start = Primitive.zr_index_operand_m(start)
      len = Primitive.zr_index_operand_m(len)
      # Past the fixnum range: rb_ary_splice's errors, or a length that
      # reaches past the end, which reads as one that reaches the end.
      unless Primitive.zr_fixnum_p_m(start) && Primitive.zr_fixnum_p_m(len)
        raise IndexError, "negative length (#{len})" if len < 0
        raise IndexError, "index #{start - Primitive.zr_ary_len_m(self)} too small for array; minimum: -#{Primitive.zr_ary_len_m(self)}" if start < 0 && start + Primitive.zr_ary_len_m(self) < 0
        raise IndexError, "index #{start} too big" unless Primitive.zr_fixnum_p_m(start)

        len = Primitive.zr_ary_len_m(self)
      end
    end
    items = value.is_a?(Array) ? value : (value.respond_to?(:to_ary) ? value.to_ary : [value])
    Primitive.zr_ary_splice(self, start, len, items)
    value
  end

  def slice!(start, len = nil)
    if len.nil?
      if start.is_a?(Range)
        part = Primitive.zr_ary_aref1_m(self, start)
        return nil if part.nil?

        from = start.begin || 0
        from += Primitive.zr_ary_len_m(self) if from < 0
        Primitive.zr_ary_splice(self, from, part.size, [])
        return part
      end
      return deleted_at(Primitive.zr_index_operand_m(start))
    end
    start = Primitive.zr_index_operand_m(start)
    len = Primitive.zr_index_operand_m(len)
    part = Primitive.zr_ary_aref2_m(self, start, len)
    return nil if part.nil?

    start += Primitive.zr_ary_len_m(self) if start < 0
    Primitive.zr_ary_splice(self, start, part.size, [])
    part
  end

  def map!
    return to_enum(:map!) { Primitive.zr_ary_len_m(self) } unless block_given?

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      Primitive.zr_ary_aset_at(self, i, yield(Primitive.zr_ary_aref1_m(self, i)))
      i += 1
    end
    self
  end

  def collect!
    return to_enum(:collect!) { Primitive.zr_ary_len_m(self) } unless block_given?

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      Primitive.zr_ary_aset_at(self, i, yield(Primitive.zr_ary_aref1_m(self, i)))
      i += 1
    end
    self
  end

  def compact!
    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| !x.nil? } ? self : nil
  end

  # As rb_ary_uniq_bang: a frozen Array refuses first; the block, when
  # given, keys each element, and an element it pushes counts too; nil
  # when nothing went.
  def uniq!(&)
    Primitive.zr_frozen_error(self) if frozen?
    return nil if Primitive.zr_ary_len_m(self) <= 1

    kept = unique(&)
    return nil if kept.size == Primitive.zr_ary_len_m(self)

    replaced(kept)
  end

  def reverse!
    Primitive.zr_frozen_error(self) if frozen?
    replaced(reversed)
  end

  # Nested Arrays (and what `to_ary` answers) spread out `depth` levels;
  # a recursive Array is an error only when the depth is unbounded.
  # A level of 0 flattens nothing, and so does an Array with no element
  # to flatten: either way the answer is a copy, a plain Array.
  def flatten(depth = nil)
    level = depth.nil? ? -1 : Numeric.send(:int_operand, depth)
    return Array.new(self) if level == 0

    result = flattened(level)
    result.equal?(self) ? Array.new(self) : result
  end

  def flatten!(depth = nil)
    Primitive.zr_frozen_error(self) if frozen?
    level = depth.nil? ? -1 : Numeric.send(:int_operand, depth)
    return nil if level == 0

    result = flattened(level)
    result.equal?(self) ? nil : replaced(result)
  end

  # CRuby's flatten: the walk keeps its own stack of (Array, index)
  # pairs, so an Array nested deeper than any call stack flattens. With
  # no level, an identity table of the Arrays open on the walk catches
  # one that holds itself. Each element answers to_ary once at most, as
  # rb_check_array_type asks it. The receiver itself when nothing
  # converts.
  def flattened(level)
    Primitive.attr! :hidden
    count = Primitive.zr_ary_len_m(self)
    i = 0
    tmp = nil
    while i < count
      tmp = Array.try_convert(Primitive.zr_ary_at_m(self, i))
      break unless tmp.nil?

      i += 1
    end
    return self if i == count

    result = Primitive.zr_ary_aref2_m(self, 0, i)
    stack = [self, i + 1]
    memo = nil
    if level < 0
      memo = {}.compare_by_identity
      memo[self] = true
      memo[tmp] = true
    end
    ary = tmp
    i = 0
    while true
      while i < Primitive.zr_ary_len_m(ary)
        elt = Primitive.zr_ary_at_m(ary, i)
        i += 1
        if level >= 0 && stack.size / 2 >= level
          result << elt
          next
        end
        tmp = Array.try_convert(elt)
        if tmp.nil?
          result << elt
        else
          if memo
            raise ArgumentError, "tried to flatten recursive array" if memo[tmp]

            memo[tmp] = true
          end
          stack << ary << i
          ary = tmp
          i = 0
        end
      end
      break if stack.empty?

      memo&.delete(ary)
      i = stack.pop
      ary = stack.pop
    end
    result
  end

  def reverse_each
    return to_enum(:reverse_each) { Primitive.zr_ary_len_m(self) } unless block_given?

    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      yield Primitive.zr_ary_aref1_m(self, i)
      i -= 1
    end
    self
  end

  def rotate(n = 1) = rotated(Primitive.zr_index_operand_m(n))

  # rb_ary_rotate_m's copy, which rotate! makes as a function.
  def rotated(n)
    Primitive.attr! :hidden
    return Array.new(self) if (Primitive.zr_ary_len_m(self) == 0)

    n %= Primitive.zr_ary_len_m(self)
    Primitive.zr_ary_aref2_m(self, n, Primitive.zr_ary_len_m(self) - n).concat(Primitive.zr_ary_aref2_m(self, 0, n))
  end

  # A Range past the end pads with nils up to its end.
  def values_at(*indexes)
    indexes.flat_map do |i|
      next [Primitive.zr_ary_aref1_m(self, Primitive.zr_index_operand_m(i))] unless i.is_a?(Range)

      first = i.begin || 0
      first += Primitive.zr_ary_len_m(self) if first < 0
      raise RangeError, "#{i} out of range" if first < 0

      last = i.end || Primitive.zr_ary_len_m(self) - 1
      last += Primitive.zr_ary_len_m(self) if last < 0
      last -= 1 if i.exclude_end? && i.end
      next [] if last < first

      (first..last).map { |j| Primitive.zr_ary_aref1_m(self, j) }
    end
  end

  def dig(index, *rest)
    v = Primitive.zr_ary_aref1_m(self, Primitive.zr_index_operand_m(index))
    rest.empty? || v.nil? ? v : Primitive.zr_dig_into(v, rest)
  end

  # Each index fetched, a block answering for one out of bounds.
  def fetch_values(*indexes, &block)
    Primitive.attr! :ruby
    indexes.map { |i| fetched(i, [], &block) }
  end

  def fetch(index, *default, &block)
    raise ArgumentError, "wrong number of arguments (given #{default.size + 1}, expected 1..2)" if default.size > 1

    fetched(index, default, &block)
  end

  # rb_ary_fetch, which fetch_values calls as a function.
  def fetched(index, default)
    Primitive.attr! :hidden

    Primitive.zr_warn_here_m("block supersedes default value argument") if block_given? && !default.empty?
    index = Primitive.zr_index_operand_m(index)
    i = index < 0 ? index + Primitive.zr_ary_len_m(self) : index
    return Primitive.zr_ary_aref1_m(self, i) if i >= 0 && i < Primitive.zr_ary_len_m(self)
    return yield(index) if block_given?
    return default[0] unless default.empty?

    raise IndexError, "index #{index} outside of array bounds: #{-Primitive.zr_ary_len_m(self)}...#{Primitive.zr_ary_len_m(self)}"
  end

  def assoc(key)
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return x if x.is_a?(Array) && x.size > 0 && Primitive.zr_rb_equal(x[0], key)

      i += 1
    end
    nil
  end

  def *(other)
    return join(other) if other.is_a?(String)

    other = Primitive.zr_index_operand_m(other)
    raise ArgumentError, "negative argument" if other < 0
    raise ArgumentError, "argument too big" if other > 0 && Primitive.zr_ary_max_size / other < Primitive.zr_ary_len_m(self)

    out = []
    other.times { out.concat(self) }
    out
  end

  def -(other)
    members = {}
    ary_operand(other).each { |x| members[x] = true }
    out = []
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      out << x unless members.key?(x)
      i += 1
    end
    out
  end

  def &(other)
    members = {}
    ary_operand(other).each { |x| members[x] = true }
    unique.select { |x| members.key?(x) }
  end

  def |(other)
    Array.new(self).concat(ary_operand(other)).uniq
  end

  # An operand as CRuby's to_ary() takes one: an Array, or what to_ary
  # gives, else a TypeError that names it.
  def ary_operand(other)
    Primitive.attr! :hidden
    converted = Array.try_convert(other)
    return converted if converted

    shown = case other
            when nil then "nil"
            when true then "true"
            when false then "false"
            else other.class
            end
    raise TypeError, "no implicit conversion of #{shown} into Array"
  end

  def zip(*others)
    columns = []
    columns << zip_column(others[columns.size], Primitive.zr_ary_len_m(self)) while columns.size < others.size
    out = []
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      row = [Primitive.zr_ary_aref1_m(self, i)]
      columns.each { |column| row << column[i] }
      block_given? ? yield(row) : out << row
      i += 1
    end
    block_given? ? nil : out
  end

  def product(*others)
    others = others.map do |other|
      Array.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Array"
    end
    mine = Array.new(self)
    combos = if others.empty?
               mine.map { |x| [x] }
             else
               rest = others[0].product(*others[1..])
               mine.flat_map { |x| rest.map { |r| [x] + r } }
             end
    return combos unless block_given?

    combos.each { |c| yield c }
    self
  end

  def transpose
    return [] if (Primitive.zr_ary_len_m(self) == 0)

    rows = map do |row|
      Array.try_convert(row) or raise TypeError, "no implicit conversion of #{conversion_name(row)} into Array"
    end
    n = rows[0].size
    rows.each { |row| raise IndexError, "element size differs (#{row.size} should be #{n})" if row.size != n }
    (0...n).map { |i| rows.map { |row| row[i] } }
  end

  # `fill(value)`, `fill(value, start [, length])`, `fill(value, range)`,
  # each with a block in place of the value.
  def fill(*args)
    value = block_given? ? nil : args.shift
    raise ArgumentError, "wrong number of arguments (given #{args.size + (block_given? ? 0 : 1)}, expected #{block_given? ? '0..2' : '1..3'})" if args.size > 2

    if args[0].is_a?(Range)
      first = args[0].begin || 0
      first += Primitive.zr_ary_len_m(self) if first < 0
      raise RangeError, "#{args[0]} out of range" if first < 0

      last = args[0].end.nil? ? Primitive.zr_ary_len_m(self) - 1 : args[0].end
      last += Primitive.zr_ary_len_m(self) if last < 0
      last -= 1 if args[0].exclude_end? && !args[0].end.nil?
      stop = last + 1
    else
      first = args[0].nil? ? 0 : Primitive.zr_index_operand_m(args[0])
      first += Primitive.zr_ary_len_m(self) if first < 0
      first = 0 if first < 0
      stop = args[1].nil? ? Primitive.zr_ary_len_m(self) : first + Primitive.zr_index_operand_m(args[1])
    end
    # rb_ary_fill's order: the receiver may change, a Range's span is at
    # least empty, a negative length fills nothing, and the span must fit.
    Primitive.zr_frozen_error(self) if frozen?
    len = stop - first
    if args[0].is_a?(Range)
      len = 0 if len < 0
    elsif len < 0
      return self
    end
    max = Primitive.zr_ary_max_size
    raise ArgumentError, "argument too big" if first >= max || len > max - first

    stop = first + len
    i = first
    while i < stop
      Primitive.zr_ary_aset_at(self, i, block_given? ? yield(i) : value)
      i += 1
    end
    self
  end

  def sort_by!
    return to_enum(:sort_by!) { Primitive.zr_ary_len_m(self) } unless block_given?

    replaced(sort_by { |x| yield(x) })
  end

  def find_index(v = nil)
    return to_enum(:find_index) if v.nil? && !block_given?

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return i if block_given? ? yield(x) : Primitive.zr_rb_equal(x, v)

      i += 1
    end
    nil
  end

  def rindex(v = nil)
    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      return i if block_given? ? yield(Primitive.zr_ary_aref1_m(self, i)) : Primitive.zr_rb_equal(Primitive.zr_ary_aref1_m(self, i), v)

      i -= 1
    end
    nil
  end

  def cycle(n = nil)
    return to_enum(:cycle, *[n].compact) { n.nil? ? ((Primitive.zr_ary_len_m(self) == 0) ? 0 : Float::INFINITY) : Primitive.zr_ary_len_m(self) * n } unless block_given?

    if n.nil?
      loop { walked { |x| yield x } } unless Primitive.zr_ary_len_m(self) == 0
    else
      Primitive.zr_index_operand_m(n).times { walked { |x| yield x } }
    end
    nil
  end

  def to_h
    h = {}
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      pair = block_given? ? yield(Primitive.zr_ary_aref1_m(self, i)) : Primitive.zr_ary_aref1_m(self, i)
      raise TypeError, "wrong element type #{pair.class} at #{i} (expected array)" unless pair.is_a?(Array)
      raise ArgumentError, "wrong array length at #{i} (expected 2, was #{pair.size})" unless pair.size == 2

      h[pair[0]] = pair[1]
      i += 1
    end
    h
  end

  # With a block, the one pass Enumerable makes.
  def minmax(&block) = block ? super : [min, max]
end

class Array
  private

  # `a[seq]` for an ArithmeticSequence, as rb_arithmetic_sequence_beg_len_step
  # bounds it and rb_ary_subseq_step reads it: a stride past 1 either way
  # raises where a Range would answer nil.
  def stride_slice(seq)
    Primitive.attr! :hidden
    first = seq.begin
    last = seq.end
    excl = seq.exclude_end?
    step = seq.step.nil? ? 1 : Primitive.zr_index_operand_m(seq.step)
    if step.negative?
      if excl && !last.nil?
        last = Primitive.zr_index_operand_m(last) + 1
        excl = false
      end
      first, last = last, first
    end
    count = Primitive.zr_ary_len_m(self)
    from = first.nil? ? 0 : Primitive.zr_index_operand_m(first)
    to = last.nil? ? -1 : Primitive.zr_index_operand_m(last)
    excl = false if last.nil?
    strict = step < -1 || step > 1
    if from.negative?
      from += count
      raise RangeError, "#{seq.inspect} out of range" if from.negative? && strict
      return nil if from.negative?
    end
    to += count if to.negative?
    to += 1 unless excl
    if strict
      raise RangeError, "#{seq.inspect} out of range" if from > count || to - from > count
    else
      return nil if from > count

      to = count if to > count
    end
    len = to - from
    len = 0 if len.negative?
    len = count - from if count < from + len
    return [] if len.zero?
    raise ArgumentError, "slice step cannot be zero" if step.zero?
    return Primitive.zr_ary_aref2_m(self, from, len) if step == 1
    return [Primitive.zr_ary_aref1_m(self, from)] if step.positive? && step >= len

    step = -len if step < -len
    at = from + (step.positive? ? 0 : len - 1)
    out = []
    ((len + step.abs - 1) / step.abs).times do
      out << Primitive.zr_ary_aref1_m(self, at)
      at += step
    end
    out
  end

  # How many elements meet the criterion, or with `negate` how many fail
  # it, counted until `enough` do.
  # Each element, by index, with the length read again each time round,
  # as the C walks an Array without `each`.
  def walked
    Primitive.attr! :hidden
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      yield Primitive.zr_ary_aref1_m(self, i)
      i += 1
    end
  end

  def meeting(pattern, block, enough, negate: false)
    Primitive.attr! :hidden
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1

    Primitive.zr_warn_here_m("given block not used") if block && !pattern.empty?
    count = 0
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      element = Primitive.zr_ary_aref1_m(self, i)
      met = if !pattern.empty? then pattern[0] === element
            elsif block then block.call(element)
            else element
            end
      if met ? !negate : negate
        count += 1
        return count if count >= enough
      end
      i += 1
    end
    count
  end

  # The walk of CRuby's select_bang_i: each element the block keeps
  # moves down over those it dropped while the Array keeps its length,
  # so the block sees every element where it was. When the walk ends,
  # even by a raise or a break, the Array is cut to what was kept and
  # whatever the walk had not reached (select_bang_ensure). True when
  # any element went.
  def sweep_by_block
    Primitive.attr! :hidden
    read = 0
    kept = 0
    begin
      while read < Primitive.zr_ary_len_m(self)
        x = Primitive.zr_ary_at_m(self, read)
        if yield(x)
          Primitive.zr_ary_aset_at(self, kept, x) if read != kept
          kept += 1
        end
        read += 1
      end
      read != kept
    ensure
      Primitive.zr_ary_splice(self, kept, read - kept, []) if kept < Primitive.zr_ary_len_m(self) && kept < read
    end
  end

  # The rest of a Float sum from element `from`, compensated as CRuby's
  # ary_add_one/Kahan-Babuska walk does; an element that is no number
  # switches to plain addition of the rest, from the sum without its
  # compensation, as CRuby's not_float does.
  def float_sum(f, x, from)
    Primitive.attr! :hidden
    c = 0.0
    i = from - 1
    loop do
      if x.is_a?(Float) || x.is_a?(Integer) || x.is_a?(Rational)
        v = x.to_f
        if v.nan? || v.infinite? || f.nan? || f.infinite?
          f += v
        else
          t = f + v
          c += (f.abs >= v.abs) ? (f - t) + v : (v - t) + f
          f = t
        end
      else
        rest = f + x
        (i + 1...Primitive.zr_ary_len_m(self)).each { |j| rest += yield(j) }
        return rest
      end
      i += 1
      break if i >= Primitive.zr_ary_len_m(self)

      x = yield(i)
    end
    f + c
  end

  def pick_repeated(k, from, chosen, &block)
    Primitive.attr! :hidden
    return yield(chosen.dup) if chosen.size == k

    (from...Primitive.zr_ary_len_m(self)).each do |i|
      chosen << Primitive.zr_ary_aref1_m(self, i)
      pick_repeated(k, i, chosen, &block)
      chosen.pop
    end
  end

  def place_repeated(k, chosen, &block)
    Primitive.attr! :hidden
    return yield(chosen.dup) if chosen.size == k

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      chosen << Primitive.zr_ary_aref1_m(self, i)
      place_repeated(k, chosen, &block)
      chosen.pop
      i += 1
    end
  end

  # The `n` smallest (`direction` 1) or largest (-1) elements, in
  # sorted order.
  def combine(k, start, chosen, &block)
    Primitive.attr! :hidden
    if chosen.size == k
      yield chosen.dup
      return
    end
    i = start
    while i <= Primitive.zr_ary_len_m(self) - (k - chosen.size)
      chosen << Primitive.zr_ary_aref1_m(self, i)
      combine(k, i + 1, chosen, &block)
      chosen.pop
      i += 1
    end
  end

  def permute(k, chosen, used, &block)
    Primitive.attr! :hidden
    if chosen.size == k
      yield chosen.dup
      return
    end
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      unless used[i]
        used[i] = true
        chosen << Primitive.zr_ary_aref1_m(self, i)
        permute(k, chosen, used, &block)
        chosen.pop
        used[i] = false
      end
      i += 1
    end
  end

  # A Range over this Array's indexes as a start and a length; a start
  # before the first element is out of range.
  def range_span(range)
    Primitive.attr! :hidden
    start = range.begin.nil? ? 0 : Primitive.zr_index_operand_m(range.begin)
    stop = range.end.nil? ? nil : Primitive.zr_index_operand_m(range.end)

    n = Primitive.zr_ary_len_m(self)
    start += n if start < 0
    raise RangeError, "#{range.inspect} out of range" if start < 0

    if stop.nil?
      stop = n
    else
      stop += n if stop < 0
      stop += 1 unless range.exclude_end?
    end
    len = stop - start
    len = 0 if len < 0
    [start, len]
  end

  # The first n items of one zip argument: an Array as it is, else
  # what its `each` yields.
  def zip_column(other, n)
    Primitive.attr! :hidden
    return other if other.is_a?(Array)
    return other.to_ary if other.respond_to?(:to_ary)
    return [] if n == 0
    raise TypeError, "wrong argument type #{other.class} (must respond to :each)" unless other.respond_to?(:each)

    out = []
    other.each do |*x|
      out << Primitive.zr_enum_value(x)
      break if out.size == n

      nil
    end
    out
  end
end
