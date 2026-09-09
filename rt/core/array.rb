# Array over the kernel's storage. CRuby writes these in C, so none
# goes through `each`: a backtrace must not show a row for it.
class Array
  include Enumerable

  def reverse
    out = []
    i = size - 1
    while i >= 0
      out << self[i]
      i -= 1
    end
    out
  end

  def last(n = nil)
    return self[-1] if n.nil?

    from = size - n
    from = 0 if from < 0
    out = []
    while from < size
      out << self[from]
      from += 1
    end
    out
  end

  def first(n = nil)
    return self[0] if n.nil?

    out = []
    i = 0
    while i < n && i < size
      out << self[i]
      i += 1
    end
    out
  end

  def <=>(other)
    return nil unless other.is_a?(Array)

    i = 0
    while i < size && i < other.size
      c = self[i] <=> other[i]
      return c if c != 0

      i += 1
    end
    size <=> other.size
  end

  def dup
    out = []
    i = 0
    while i < size
      out << self[i]
      i += 1
    end
    out
  end

  def +(other)
    out = dup
    i = 0
    while i < other.size
      out << other[i]
      i += 1
    end
    out
  end

  def join(sep = "")
    s = +""
    i = 0
    while i < size
      s << sep if i > 0
      x = self[i]
      s << (x.is_a?(Array) ? x.join(sep) : x.to_s)
      i += 1
    end
    s
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
      return i if block_given? ? yield(self[i]) : self[i] == v

      i += 1
    end
    nil
  end

  def sum(init = 0)
    acc = init
    i = 0
    while i < size
      acc += block_given? ? yield(self[i]) : self[i]
      i += 1
    end
    acc
  end

  def min
    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || (block_given? ? yield(self[i], best) : self[i] <=> best) < 0
      i += 1
    end
    best
  end

  def max
    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || (block_given? ? yield(self[i], best) : self[i] <=> best) > 0
      i += 1
    end
    best
  end

  def take(n) = first(n)

  def drop(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

    out = []
    i = n
    while i < size
      out << self[i]
      i += 1
    end
    out
  end

  def uniq
    out = []
    i = 0
    while i < size
      out << self[i] unless out.include?(self[i])
      i += 1
    end
    out
  end

  def include?(v)
    i = 0
    while i < size
      return true if self[i] == v

      i += 1
    end
    false
  end

  def eql?(other)
    return false unless other.is_a?(Array) && size == other.size

    i = 0
    while i < size
      return false unless self[i].eql?(other[i])

      i += 1
    end
    true
  end

  def hash
    h = 7
    i = 0
    while i < size
      h = (h * 31 + self[i].hash) & 4611686018427387903
      i += 1
    end
    h
  end

  def to_a = self
  def count(*args, &block) = args.empty? && !block ? size : super

  def shift(n = nil)
    if n.nil?
      return nil if empty?

      first = self[0]
      Primitive.zr_ary_splice(self, 0, 1, [])
      return first
    end
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

  def insert(index, *vals)
    return self if vals.empty?

    index = size + index + 1 if index < 0
    Primitive.zr_ary_splice(self, index, 0, vals)
  end

  def concat(*others)
    others.each { |o| Primitive.zr_ary_splice(self, size, 0, o) }
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
      if self[i] == v
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

    i = 0
    while i < size
      if yield(self[i])
        Primitive.zr_ary_splice(self, i, 1, [])
      else
        i += 1
      end
    end
    self
  end

  def reject!
    return to_enum(:reject!) { size } unless block_given?

    before = size
    delete_if { |x| yield(x) }
    size == before ? nil : self
  end

  def select!
    return to_enum(:select!) { size } unless block_given?

    before = size
    delete_if { |x| !yield(x) }
    size == before ? nil : self
  end

  def keep_if
    select! { |x| yield(x) }
    self
  end

  def filter! = select! { |x| yield(x) }

  def clear = Primitive.zr_ary_clear(self, nil)

  def replace(other)
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
      raise TypeError, "no implicit conversion of #{start.class} into Integer" unless start.is_a?(Integer)
      raise TypeError, "no implicit conversion of #{len.class} into Integer" unless len.is_a?(Integer)
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

  def collect! = map! { |x| yield(x) }

  def compact!
    before = size
    delete_if(&:nil?)
    size == before ? nil : self
  end

  def uniq!
    before = size
    replace(uniq)
    size == before ? nil : self
  end

  def reverse!
    replace(reverse)
  end

  def flatten(depth = -1)
    out = []
    seen = []
    walk = lambda do |a, d|
      raise ArgumentError, "tried to flatten recursive array" if seen.any? { |s| s.equal?(a) }

      seen << a
      i = 0
      while i < a.size
        x = a[i]
        if x.is_a?(Array) && d != 0
          walk.call(x, d - 1)
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
    return nil if none? { |x| x.is_a?(Array) }

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
    return dup if empty?

    n %= size
    self[n, size - n] + self[0, n]
  end

  def values_at(*indexes)
    indexes.map { |i| i.is_a?(Range) ? self[i] : self[i] }.flatten(1)
  end

  def dig(index, *rest)
    v = self[index]
    rest.empty? || v.nil? ? v : v.dig(*rest)
  end

  def fetch(index, *default)
    raise ArgumentError, "wrong number of arguments (given #{default.size + 1}, expected 1..2)" if default.size > 1

    i = index < 0 ? index + size : index
    return self[i] if i >= 0 && i < size
    return yield(index) if block_given?
    return default[0] unless default.empty?

    raise IndexError, "index #{index} outside of array bounds: #{-size}...#{size}"
  end

  def assoc(key)
    each { |x| return x if x.is_a?(Array) && x[0] == key }
    nil
  end

  def *(other)
    return join(other) if other.is_a?(String)
    raise ArgumentError, "negative argument" if other < 0

    out = []
    other.times { out.concat(self) }
    out
  end

  def -(other)
    reject { |x| other.include?(x) }
  end

  def &(other)
    uniq.select { |x| other.include?(x) }
  end

  def |(other)
    (self + other).uniq
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
    return map { |x| [x] } if others.empty?

    rest = others[0].product(*others[1..])
    flat_map { |x| rest.map { |r| [x] + r } }
  end

  def transpose
    return [] if empty?

    n = self[0].size
    each { |row| raise IndexError, "element size differs (#{row.size} should be #{n})" if row.size != n }
    (0...n).map { |i| map { |row| row[i] } }
  end

  def fill(value = nil, start = 0, length = nil)
    if block_given?
      i = start
      stop = length ? start + length : size
      while i < stop
        self[i] = yield(i)
        i += 1
      end
    else
      i = start
      stop = length ? start + length : size
      while i < stop
        self[i] = value
        i += 1
      end
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
      return i if block_given? ? yield(self[i]) : self[i] == v

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

  def minmax = [min, max]
end

class Array
  private

  # A Range over this Array's indexes as a start and a length; a start
  # before the first element is out of range.
  def range_span(range)
    Primitive.attr! :hidden
    start = range.begin || 0
    stop = range.end
    raise TypeError, "no implicit conversion of #{start.class} into Integer" unless start.is_a?(Integer)
    raise TypeError, "no implicit conversion of #{stop.class} into Integer" unless stop.nil? || stop.is_a?(Integer)

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
