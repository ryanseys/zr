# Array over the kernel's storage. CRuby writes these in C, so none
# goes through `each`: a backtrace must not show a row for it.
class Array
  include Enumerable

  # Ruby owns these on Array itself, so a later definition on Enumerable
  # does not shadow them. The bodies are Enumerable's.
  %i[all? any? detect drop_while none? one? take_while].each do |name|
    define_method(name, Enumerable.instance_method(name))
  end

  def reverse
    out = []
    i = size - 1
    while i >= 0
      out << self[i]
      i -= 1
    end
    out
  end

  def last(n = (none = true))
    return self[-1] if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    from = size - n
    from = 0 if from < 0
    out = []
    while from < size
      out << self[from]
      from += 1
    end
    out
  end

  def first(n = (none = true))
    return self[0] if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    out = []
    i = 0
    while i < n && i < size
      out << self[i]
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
      while i < size && i < other.size
        c = self[i] <=> other[i]
        return c if c != 0

        i += 1
      end
      size <=> other.size
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

  def at(index) = self[Primitive.zr_index_operand_m(index)]

  def join(sep = nil)
    sep = $, if sep.nil?
    sep = sep.nil? ? "" : Primitive.zr_str_operand(sep)
    raise ArgumentError, "recursive array join" if Primitive.zr_recursive_enter(self, :join)

    begin
      s = +""
      i = 0
      while i < size
        s << sep if i > 0
        x = self[i]
        s << if x.is_a?(Array)
               x.join(sep)
             elsif x.is_a?(String)
               x
             elsif x.respond_to?(:to_str)
               x.to_str
             elsif x.respond_to?(:to_ary)
               x.to_ary.join(sep)
             else
               Primitive.zr_obj_as_string(x)
             end
        i += 1
      end
      s
    ensure
      Primitive.zr_recursive_leave(self, :join)
    end
  end

  def compact
    out = []
    i = 0
    while i < size
      out << self[i] unless self[i].nil?
      i += 1
    end
    out
  end

  def index(v = nil)
    return to_enum(:index) if v.nil? && !block_given?

    i = 0
    while i < size
      x = self[i]
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
    while i < size
      x = block_given? ? yield(self[i]) : self[i]
      if acc.is_a?(Float) || (x.is_a?(Float) && (acc.is_a?(Integer) || acc.is_a?(Rational)))
        return float_sum(acc.to_f, x, i + 1) { |j| block_given? ? yield(self[j]) : self[j] }
      end
      acc += x
      i += 1
    end
    acc
  end

  def min(n = nil, &block)
    return ranked(n, block, 1) unless n.nil?

    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || compared(self[i], best, block) < 0
      i += 1
    end
    best
  end

  def max(n = nil, &block)
    return ranked(n, block, -1) unless n.nil?

    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || compared(self[i], best, block) > 0
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
    replace(rotate(n))
  end

  def rassoc(value)
    each { |row| return row if row.is_a?(Array) && row.size > 1 && Primitive.zr_rb_equal(row[1], value) }
    nil
  end

  def bsearch(&block)
    return to_enum(:bsearch) unless block

    at = bsearch_index(&block)
    at && self[at]
  end

  # Binary search in find-minimum mode (the block answers true or
  # false) or find-any mode (the block answers a number's sign).
  def bsearch_index
    return to_enum(:bsearch_index) unless block_given?

    low = 0
    high = size
    found = nil
    while low < high
      mid = low + (high - low) / 2
      answer = yield(self[mid])
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

  def intersection(*others) = others.inject(self) { |acc, other| acc & other }

  def union(*others) = others.inject(uniq) { |acc, other| acc | other }

  def difference(*others) = others.inject(self) { |acc, other| acc - other }

  def intersect?(other) = !(self & other).empty?

  def repeated_combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:repeated_combination, k) { k < 0 ? 0 : (k == 0 ? 1 : (size + k - 1).downto(size).inject(1) { |a, b| a * b } / (1..k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && !empty?
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
        n.negative? ? 0 : size**n
      end
    end

    k = Primitive.zr_index_operand_m(k)
    if k == 0
      yield []
    elsif k > 0 && !empty?
      place_repeated(k, []) { |c| yield c }
    end
    self
  end

  def combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:combination, k) { k < 0 || k > size ? 0 : (1..size).inject(1) { |a, b| a * b } / ((1..k).inject(1) { |a, b| a * b } * (1..size - k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && k <= size
      combine(k, 0, []) { |c| yield c }
    end
    self
  end

  def permutation(k = size)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:permutation, k) { k < 0 || k > size ? 0 : (size - k + 1..size).inject(1) { |a, b| a * b } } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && k <= size
      permute(k, [], Array.new(size, false)) { |c| yield c }
    end
    self
  end

  def take(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

    first(n)
  end

  def drop(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

    out = []
    i = n
    while i < size
      out << self[i]
      i += 1
    end
    out
  end

  def deconstruct = self

  def slice(*args) = self[*args]

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
    raise TypeError, "can't convert #{object.class} to Array (#{object.class}#to_ary gives #{converted.class})" unless converted.nil? || converted.is_a?(Array)

    converted
  end

  def to_ary = self

  # Membership here is by `hash` and `eql?`, as CRuby's set
  # operations decide it.
  def uniq
    return Array.new(self) if size <= 1 && !block_given?

    seen = {}
    out = []
    i = 0
    while i < size
      x = self[i]
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
    while i < size
      x = self[i]
      return true if Primitive.zr_rb_equal(x, v)

      i += 1
    end
    false
  end

  def eql?(other)
    return false unless other.is_a?(Array) && size == other.size
    return true if equal?(other) || Primitive.zr_recursive_enter(self, :eql?)

    begin
      i = 0
      while i < size
        return false unless self[i].eql?(other[i])

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
      while i < size
        h = (h * 31 + (self[i].hash & mask)) & mask
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
    return size if none && !block

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

    out = last(n)
    Primitive.zr_ary_splice(self, size - out.size, out.size, [])
    out
  end

  def shift(n = (none = true))
    if none
      return nil if empty?

      first = self[0]
      Primitive.zr_ary_splice(self, 0, 1, [])
      return first
    end
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative array size" if n < 0

    out = first(n)
    Primitive.zr_ary_splice(self, 0, out.size, [])
    out
  end

  def unshift(*vals)
    Primitive.zr_ary_splice(self, 0, 0, vals)
  end

  def prepend(*vals) = unshift(*vals)

  def append(*vals) = push(*vals)

  # A frozen receiver refuses before the index is read, and an index
  # below `-size - 1` names no place to insert at.
  def insert(index, *vals)
    Primitive.zr_frozen_error(self) if frozen?
    index = Primitive.zr_index_operand_m(index)
    return self if vals.empty?

    if index.negative?
      raise IndexError, "index #{index} too small for array; minimum: #{-size - 1}" if index < -size - 1

      index += size + 1
    end
    Primitive.zr_ary_splice(self, index, 0, vals)
  end

  # The arguments are read before any is appended, so `a.concat(a, a)`
  # triples it.
  def concat(*others)
    pieces = others.map do |o|
      ary = Array.try_convert(o) || raise(TypeError, "no implicit conversion of #{conversion_name(o)} into Array")
      ary.equal?(self) ? ary.dup : ary
    end
    pieces.each { |o| Primitive.zr_ary_splice(self, size, 0, o) }
    self
  end

  def delete_at(index)
    index += size if index < 0
    return nil if index < 0 || index >= size

    v = self[index]
    Primitive.zr_ary_splice(self, index, 1, [])
    v
  end

  def delete(v)
    found = nil
    i = 0
    while i < size
      if Primitive.zr_rb_equal(self[i], v)
        found = self[i]
        Primitive.zr_ary_splice(self, i, 1, [])
      else
        i += 1
      end
    end
    found.nil? && block_given? ? yield(v) : found
  end

  def delete_if
    return to_enum(:delete_if) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| !yield(x) }
    self
  end

  def reject!
    return to_enum(:reject!) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| !yield(x) } ? self : nil
  end

  def select!
    return to_enum(:select!) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    sweep_by_block { |x| yield(x) } ? self : nil
  end

  def keep_if
    return to_enum(:keep_if) { size } unless block_given?

    select! { |x| yield(x) }
    self
  end

  def filter!(&block)
    return to_enum(:filter!) { size } unless block

    select!(&block)
  end

  def clear = Primitive.zr_ary_clear(self, nil)

  def replace(other)
    other = Array.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Array"
    Primitive.zr_ary_splice(self, 0, size, other)
  end

  # `a[i] = v`, `a[start, len] = v` and `a[range] = v`: the span's
  # elements leave and the value's elements, or the value, take their
  # place.
  def []=(*args)
    case args.size
    when 2
      index, value = args
      return Primitive.zr_ary_aset_at(self, index, value) unless index.is_a?(Range)

      start, len = range_span(index)
    when 3
      start, len, value = args
      start = Primitive.zr_index_operand_m(start)
      len = Primitive.zr_index_operand_m(len)
    else
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)"
    end
    items = value.is_a?(Array) ? value : (value.respond_to?(:to_ary) ? value.to_ary : [value])
    Primitive.zr_ary_splice(self, start, len, items)
    value
  end

  def slice!(start, len = nil)
    if len.nil?
      if start.is_a?(Range)
        part = self[start]
        return nil if part.nil?

        from = start.begin || 0
        from += size if from < 0
        Primitive.zr_ary_splice(self, from, part.size, [])
        return part
      end
      return delete_at(start)
    end
    part = self[start, len]
    return nil if part.nil?

    start += size if start < 0
    Primitive.zr_ary_splice(self, start, part.size, [])
    part
  end

  def map!
    return to_enum(:map!) { size } unless block_given?

    i = 0
    while i < size
      self[i] = yield(self[i])
      i += 1
    end
    self
  end

  def collect!(&block)
    return to_enum(:collect!) { size } unless block

    map!(&block)
  end

  def compact!
    Primitive.zr_frozen_error(self) if frozen?
    before = size
    delete_if(&:nil?)
    size == before ? nil : self
  end

  # As rb_ary_uniq_bang: a frozen Array refuses first; the block, when
  # given, keys each element, and an element it pushes counts too; nil
  # when nothing went.
  def uniq!(&)
    Primitive.zr_frozen_error(self) if frozen?
    return nil if size <= 1

    kept = uniq(&)
    return nil if kept.size == size

    replace(kept)
  end

  def reverse!
    replace(reverse)
  end

  # Nested Arrays (and what `to_ary` answers) spread out `depth` levels;
  # a recursive Array is an error only when the depth is unbounded.
  def flatten(depth = -1)
    depth = Primitive.zr_index_operand_m(depth) unless depth.nil?
    depth = -1 if depth.nil?
    out = []
    seen = []
    walk = lambda do |a, d|
      raise ArgumentError, "tried to flatten recursive array" if d < 0 && seen.any? { |s| s.equal?(a) }

      seen << a
      i = 0
      while i < a.size
        x = a[i]
        inner = x.is_a?(Array) ? x : (d != 0 && x.respond_to?(:to_ary) ? Array.try_convert(x) : nil)
        if inner && d != 0
          walk.call(inner, d - 1)
        else
          out << x
        end
        i += 1
      end
      seen.pop
    end
    walk.call(self, depth)
    out
  end

  def flatten!(depth = -1)
    Primitive.zr_frozen_error(self) if frozen?
    return nil if none? { |x| x.is_a?(Array) || x.respond_to?(:to_ary) }

    replace(flatten(depth))
  end

  def reverse_each
    return to_enum(:reverse_each) { size } unless block_given?

    i = size - 1
    while i >= 0
      yield self[i]
      i -= 1
    end
    self
  end

  def each_slice(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "invalid slice size" if n <= 0
    return to_enum(:each_slice, n) { (size + n - 1) / n } unless block_given?

    i = 0
    while i < size
      yield self[i, n]
      i += n
    end
    self
  end

  def rotate(n = 1)
    n = Primitive.zr_index_operand_m(n)
    return Array.new(self) if empty?

    n %= size
    self[n, size - n] + self[0, n]
  end

  # A Range past the end pads with nils up to its end.
  def values_at(*indexes)
    indexes.flat_map do |i|
      next [self[Primitive.zr_index_operand_m(i)]] unless i.is_a?(Range)

      first = i.begin || 0
      first += size if first < 0
      raise RangeError, "#{i} out of range" if first < 0

      last = i.end || size - 1
      last += size if last < 0
      last -= 1 if i.exclude_end? && i.end
      next [] if last < first

      (first..last).map { |j| self[j] }
    end
  end

  def dig(index, *rest)
    v = self[index]
    rest.empty? || v.nil? ? v : Primitive.zr_dig_into(v, rest)
  end

  # Each index fetched, a block answering for one out of bounds.
  def fetch_values(*indexes, &block)
    indexes.map { |i| block ? fetch(i, &block) : fetch(i) }
  end

  # The last element the block accepts, or nil.
  def rfind
    return to_enum(:rfind) { size } unless block_given?

    reverse_each { |v| return v if yield(v) }
    nil
  end

  def fetch(index, *default)
    raise ArgumentError, "wrong number of arguments (given #{default.size + 1}, expected 1..2)" if default.size > 1

    Primitive.zr_warn_here_m("block supersedes default value argument") if block_given? && !default.empty?
    index = Primitive.zr_index_operand_m(index)
    i = index < 0 ? index + size : index
    return self[i] if i >= 0 && i < size
    return yield(index) if block_given?
    return default[0] unless default.empty?

    raise IndexError, "index #{index} outside of array bounds: #{-size}...#{size}"
  end

  def assoc(key)
    each { |x| return x if x.is_a?(Array) && x.size > 0 && Primitive.zr_rb_equal(x[0], key) }
    nil
  end

  def *(other)
    return join(other) if other.is_a?(String)

    other = Primitive.zr_index_operand_m(other)
    raise ArgumentError, "negative argument" if other < 0
    raise ArgumentError, "argument too big" if other > 0 && Primitive.zr_ary_max_size / other < size

    out = []
    other.times { out.concat(self) }
    out
  end

  def -(other)
    members = {}
    other.to_ary.each { |x| members[x] = true }
    reject { |x| members.key?(x) }
  end

  def &(other)
    members = {}
    other.to_ary.each { |x| members[x] = true }
    uniq.select { |x| members.key?(x) }
  end

  def |(other)
    (self + other.to_ary).uniq
  end

  def zip(*others)
    columns = []
    columns << zip_column(others[columns.size], size) while columns.size < others.size
    out = []
    i = 0
    while i < size
      row = [self[i]]
      columns.each { |column| row << column[i] }
      block_given? ? yield(row) : out << row
      i += 1
    end
    block_given? ? nil : out
  end

  def product(*others)
    others = others.map do |other|
      Array.try_convert(other) or raise TypeError, "no implicit conversion of #{other.class} into Array"
    end
    combos = if others.empty?
               map { |x| [x] }
             else
               rest = others[0].product(*others[1..])
               flat_map { |x| rest.map { |r| [x] + r } }
             end
    return combos unless block_given?

    combos.each { |c| yield c }
    self
  end

  def transpose
    return [] if empty?

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
      first += size if first < 0
      raise RangeError, "#{args[0]} out of range" if first < 0

      last = args[0].end.nil? ? size - 1 : args[0].end
      last += size if last < 0
      last -= 1 if args[0].exclude_end? && !args[0].end.nil?
      stop = last + 1
    else
      first = args[0].nil? ? 0 : Primitive.zr_index_operand_m(args[0])
      first += size if first < 0
      first = 0 if first < 0
      stop = args[1].nil? ? size : first + Primitive.zr_index_operand_m(args[1])
    end
    if stop > first
      max = Primitive.zr_ary_max_size
      raise ArgumentError, "argument too big" if first >= max || stop - first > max - first
    end
    i = first
    while i < stop
      self[i] = block_given? ? yield(i) : value
      i += 1
    end
    self
  end

  def sort_by!
    return to_enum(:sort_by!) { size } unless block_given?

    replace(sort_by { |x| yield(x) })
  end

  def find_index(v = nil)
    return to_enum(:find_index) if v.nil? && !block_given?

    block_given? ? index { |x| yield(x) } : index(v)
  end

  def rindex(v = nil)
    i = size - 1
    while i >= 0
      return i if block_given? ? yield(self[i]) : Primitive.zr_rb_equal(self[i], v)

      i -= 1
    end
    nil
  end

  def cycle(n = nil)
    return to_enum(:cycle, *[n].compact) { n.nil? ? (empty? ? 0 : Float::INFINITY) : size * n } unless block_given?

    if n.nil?
      loop { each { |x| yield x } } unless empty?
    else
      n.times { each { |x| yield x } }
    end
    nil
  end

  def to_h
    h = {}
    i = 0
    while i < size
      pair = block_given? ? yield(self[i]) : self[i]
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
      while read < size
        x = Primitive.zr_ary_at_m(self, read)
        if yield(x)
          Primitive.zr_ary_aset_at(self, kept, x) if read != kept
          kept += 1
        end
        read += 1
      end
      read != kept
    ensure
      Primitive.zr_ary_splice(self, kept, read - kept, []) if kept < size && kept < read
    end
  end

  # The rest of a Float sum from element `from`, compensated as CRuby's
  # ary_add_one/Kahan-Babuska walk does; a non-Float element switches
  # to plain addition of the rest.
  def float_sum(f, x, from)
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
        rest = f + c + x
        (i + 1...size).each { |j| rest += yield(j) }
        return rest
      end
      i += 1
      break if i >= size

      x = yield(i)
    end
    f + c
  end

  def pick_repeated(k, from, chosen, &block)
    return yield(chosen.dup) if chosen.size == k

    (from...size).each do |i|
      chosen << self[i]
      pick_repeated(k, i, chosen, &block)
      chosen.pop
    end
  end

  def place_repeated(k, chosen, &block)
    return yield(chosen.dup) if chosen.size == k

    each do |x|
      chosen << x
      place_repeated(k, chosen, &block)
      chosen.pop
    end
  end

  # The `n` smallest (`direction` 1) or largest (-1) elements, in
  # sorted order.
  def ranked(n, block, direction)
    Primitive.attr! :hidden
    raise ArgumentError, "negative size (#{n})" if n < 0

    ordered = block ? sort { |a, b| direction * block.call(a, b) } : sort { |a, b| direction * (a <=> b) }
    ordered.first(n)
  end

  def combine(k, start, chosen, &block)
    Primitive.attr! :hidden
    if chosen.size == k
      yield chosen.dup
      return
    end
    i = start
    while i <= size - (k - chosen.size)
      chosen << self[i]
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
    while i < size
      unless used[i]
        used[i] = true
        chosen << self[i]
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

    n = size
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
