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

  def find(ifnone = nil)
    return to_enum(:find, ifnone) unless block_given?

    each do |*x|
      x = Primitive.zr_enum_value(x)
      return x if yield(x)
      nil
    end
    ifnone&.call
  end

  def any?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return true if pattern[0] === x
        nil
      end
    elsif block_given?
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

  def all?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false unless pattern[0] === x
        nil
      end
    elsif block_given?
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

  def none?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return false if pattern[0] === x
        nil
      end
    elsif block_given?
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

  def count(*args)
    n = 0
    if !args.empty?
      item = args[0]
      each do |*x|
        x = Primitive.zr_enum_value(x)
        n += 1 if x == item
        nil
      end
    elsif block_given?
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
    return to_enum(:each_with_object, memo) { respond_to?(:size) ? size : nil } unless block_given?

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
    n = Primitive.zr_index_operand_m(n)
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
    n = Primitive.zr_index_operand_m(n)
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

  def min_by(n = nil, &block)
    return to_enum(:min_by, n) unless block
    raise ArgumentError, "negative size (#{n})" if !n.nil? && n < 0
    return sort_by(&block).first(n) unless n.nil?

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

  def max_by(n = nil, &block)
    return to_enum(:max_by, n) unless block
    raise ArgumentError, "negative size (#{n})" if !n.nil? && n < 0
    return sort_by(&block).reverse.first(n) unless n.nil?

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

  def min(n = nil, &blk)
    to_a.min(n, &blk)
  end

  def max(n = nil, &blk)
    to_a.max(n, &blk)
  end

  def minmax(&block) = [min(&block), max(&block)]

  def one?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    seen = 0
    if !pattern.empty?
      each do |*x|
        x = Primitive.zr_enum_value(x)
        seen += 1 if pattern[0] === x
        nil
      end
    elsif block_given?
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

  def tally(counts = nil)
    unless counts.nil?
      raise TypeError, "no implicit conversion of #{counts.class} into Hash" unless counts.is_a?(Hash)
      Primitive.zr_frozen_error(counts) if counts.frozen?

      each do |*x|
        x = Primitive.zr_enum_value(x)
        counts[x] = (counts[x] || 0) + 1
        nil
      end
      return counts
    end
    out = {}
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out[x] = (out[x] || 0) + 1
      nil
    end
    out
  end

  def zip(*others, &block)
    to_a.zip(*others, &block)
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

  def sum(init = 0)
    acc = init
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

module Enumerable
  alias collect map
  alias filter select
  alias find_all select
  alias detect find
  alias member? include?

  def to_h(&block)
    out = {}
    each do |*x|
      pair = Primitive.zr_enum_value(x)
      pair = yield(pair) if block
      raise TypeError, "wrong element type #{pair.class} (expected array)" unless pair.is_a?(Array)
      raise ArgumentError, "element has wrong array length (expected 2, was #{pair.size})" unless pair.size == 2

      out[pair[0]] = pair[1]
      nil
    end
    out
  end

  def compact
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      out << x unless x.nil?
      nil
    end
    out
  end

  def reverse_each(&block)
    return to_enum(:reverse_each) unless block

    to_a.reverse_each(&block)
    self
  end

  def cycle(n = nil)
    return to_enum(:cycle, n) unless block_given?

    items = to_a
    return nil if items.empty?

    if n.nil?
      while true
        items.each { |x| yield x }
      end
    else
      n.times { items.each { |x| yield x } }
      nil
    end
  end

  def minmax_by(&block)
    return to_enum(:minmax_by) unless block

    [min_by(&block), max_by(&block)]
  end

  def grep(pattern)
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      if pattern === x
        out << (block_given? ? yield(x) : x)
      end
      nil
    end
    out
  end

  def grep_v(pattern)
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      unless pattern === x
        out << (block_given? ? yield(x) : x)
      end
      nil
    end
    out
  end

  def chunk_while
    raise ArgumentError, "tried to create Proc object without a block" unless block_given?

    items = to_a
    out = []
    items.each_with_index do |x, i|
      if i.zero? || !yield(items[i - 1], x)
        out << [x]
      else
        out.last << x
      end
    end
    Enumerator.new { |y| out.each { |slice| y << slice } }
  end

  def slice_when
    raise ArgumentError, "tried to create Proc object without a block" unless block_given?

    items = to_a
    out = []
    items.each_with_index do |x, i|
      if i.zero? || yield(items[i - 1], x)
        out << [x]
      else
        out.last << x
      end
    end
    Enumerator.new { |y| out.each { |slice| y << slice } }
  end

  def slice_before(pattern = nil, &block)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if pattern.nil? && block.nil?

    test = pattern ? ->(x) { pattern === x } : block
    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      if out.empty? || test.call(x)
        out << [x]
      else
        out.last << x
      end
      nil
    end
    Enumerator.new { |y| out.each { |slice| y << slice } }
  end

  def slice_after(pattern = nil, &block)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if pattern.nil? && block.nil?

    test = pattern ? ->(x) { pattern === x } : block
    out = []
    open = false
    each do |*x|
      x = Primitive.zr_enum_value(x)
      if open
        out.last << x
      else
        out << [x]
      end
      open = !test.call(x)
      nil
    end
    Enumerator.new { |y| out.each { |slice| y << slice } }
  end

  def chunk
    return to_enum(:chunk) unless block_given?

    out = []
    each do |*x|
      x = Primitive.zr_enum_value(x)
      key = yield(x)
      if key.nil? || key == :_separator
        out << nil unless out.empty? || out.last.nil?
      elsif key == :_alone
        out << [key, [x]]
      elsif !out.empty? && !out.last.nil? && out.last[0] == key && key != :_alone
        out.last[1] << x
      else
        out << [key, [x]]
      end
      nil
    end
    Enumerator.new { |y| out.compact.each { |pair| y << pair } }
  end

  def chain(*others) = Enumerator::Chain.new(self, *others)

  def lazy = Enumerator::Lazy.from(self)

  def to_set(&block) = Set.new(self, &block)
end
