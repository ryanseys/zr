# Enumerable over `each`, in the shape CRuby's C implementation has: a
# block passed on to `each`, with what it yields taken as the element,
# packed into an Array when there are several. Each such block answers
# nil, so an `each` that stops on a truthy answer, as `find_index`
# does, sees every element.
module Enumerable
  def map
    return to_enum(:map) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << yield(x)
      nil
    end
    out
  end

  def select
    return to_enum(:select) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x if yield(x)
      nil
    end
    out
  end

  def reject
    return to_enum(:reject) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x unless yield(x)
      nil
    end
    out
  end

  def filter_map
    return to_enum(:filter_map) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      v = yield(x)
      out << v if v
      nil
    end
    out
  end

  def find
    return to_enum(:find) unless block_given?

    each do |*x|
      x = Primitive.zr_enum_value(x)
      return x if yield(x)
      nil
    end
    nil
  end

  def any?
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return true if yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return true if x
        nil
      end
    end
    false
  end

  def all?
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false unless yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false unless x
        nil
      end
    end
    true
  end

  def none?
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false if yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false if x
        nil
      end
    end
    true
  end

  def count
    n = 0
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        n += 1 if yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        n += 1
        nil
      end
    end
    n
  end

  def sort(&blk)
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x
      nil
    end
    Primitive.zr_ary_sort_copy(out, blk)
  end

  def sort_by
    return to_enum(:sort_by) unless block_given?

    pairs = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      pairs << yield(x) << x
      nil
    end
    Primitive.zr_sort_by(pairs)
  end

  def take_while
    return to_enum(:take_while) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      break unless yield(x)

      out << x
      nil
    end
    out
  end

  def drop_while
    return to_enum(:drop_while) unless block_given?

    out = []
    dropping = true
    each do |*x|
      x = Primitive.zr_enum_value(x)
      dropping = false if dropping && !yield(x)
      out << x unless dropping
      nil
    end
    out
  end

  def each_with_object(memo)
    return to_enum(:each_with_object, memo) unless block_given?

    each do |*x|
      x = Primitive.zr_enum_value(x)
      yield(x, memo)
      nil
    end
    memo
  end

  def flat_map
    return to_enum(:flat_map) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      v = yield(x)
      v.is_a?(Array) ? out.concat(v) : out << v
      nil
    end
    out
  end

  def collect_concat = flat_map { |x| yield(x) }

  def group_by
    return to_enum(:group_by) unless block_given?

    out = {}
    each do |*x|
      x = Primitive.zr_enum_value(x)
      k = yield(x)
      (out[k] ||= []) << x
      nil
    end
    out
  end

  def partition
    return to_enum(:partition) unless block_given?

    yes = []
    no = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      (yield(x) ? yes : no) << x
      nil
    end
    [yes, no]
  end

  def each_cons(n)
    raise ArgumentError, "invalid size" if n <= 0
    return to_enum(:each_cons, n) { [count - n + 1, 0].max } unless block_given?

    window = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      window << x
      window.shift if window.size > n
      yield window.dup if window.size == n
      nil
    end
    self
  end

  def each_slice(n)
    raise ArgumentError, "invalid slice size" if n <= 0
    return to_enum(:each_slice, n) { (count + n - 1) / n } unless block_given?

    slice = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      slice << x
      if slice.size == n
        yield slice
        slice = []
      end
      nil
    end
    yield slice unless slice.empty?
    self
  end

  def each_entry
    return to_enum(:each_entry) unless block_given?

    each do |*x|
      x = Primitive.zr_enum_value(x)
      yield x
      nil
    end
    self
  end

  def min_by
    return to_enum(:min_by) unless block_given?

    best = nil
    key = nil
    first = true
    each do |*x|
      x = Primitive.zr_enum_value(x)
      k = yield(x)
      if first || (k <=> key) < 0
        best = x
        key = k
        first = false
      end
      nil
    end
    best
  end

  def max_by
    return to_enum(:max_by) unless block_given?

    best = nil
    key = nil
    first = true
    each do |*x|
      x = Primitive.zr_enum_value(x)
      k = yield(x)
      if first || (k <=> key) > 0
        best = x
        key = k
        first = false
      end
      nil
    end
    best
  end

  def min(&blk)
    to_a.min(&blk)
  end

  def max(&blk)
    to_a.max(&blk)
  end

  def minmax = [min, max]

  def one?
    seen = 0
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        seen += 1 if yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        seen += 1 if x
        nil
      end
    end
    seen == 1
  end

  def tally
    out = {}
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out[x] = (out[x] || 0) + 1
      nil
    end
    out
  end

  def zip(*others)
    to_a.zip(*others)
  end

  def take(n)
    out = []
    return out if n == 0

    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x
      break if out.size >= n
      nil
    end
    out
  end

  def drop(n)
    out = []
    i = 0
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x if i >= n
      i += 1
      nil
    end
    out
  end

  def find_index(v = nil)
    return to_enum(:find_index) if v.nil? && !block_given?

    i = 0
    each do |*x|
      x = Primitive.zr_enum_value(x)
      return i if block_given? ? yield(x) : x == v

      i += 1
      nil
    end
    nil
  end

  def uniq
    to_a.uniq
  end

  def entries = to_a

  def first(n = nil)
    if n.nil?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return x
        nil
      end
      return nil
    end
    take(n)
  end

  def to_a
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x
      nil
    end
    out
  end

  def include?(target)
    each do |*x|
      x = Primitive.zr_enum_value(x)
      return true if x == target
      nil
    end
    false
  end

  def each_with_index
    return to_enum(:each_with_index) unless block_given?

    i = 0
    each do |*x|
      x = Primitive.zr_enum_value(x)
      yield(x, i)
      i += 1
      nil
    end
    self
  end

  def inject(*args)
    acc = args.empty? ? nil : args.first
    op = args.size == 2 ? args.last : (args.size == 1 && !block_given? ? args.first : nil)
    if op
      acc = args.size == 2 ? args.first : nil
      first = args.size != 2
      each do |*x|
        x = Primitive.zr_enum_value(x)
        if first
          acc = x
          first = false
        else
          acc = acc.send(op, x)
        end
        nil
      end
      return acc
    end
    first = args.empty?
    each do |*x|
      x = Primitive.zr_enum_value(x)
      if first
        acc = x
        first = false
      else
        acc = yield(acc, x)
      end
      nil
    end
    acc
  end

  def reduce(*args, &block) = inject(*args, &block)

  def sum
    acc = 0
    if block_given?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        acc += yield(x)
        nil
      end
    else
      each do |*x|
        x = Primitive.zr_enum_value(x)
        acc += x
        nil
      end
    end
    acc
  end
end
