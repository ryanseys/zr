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
      out << yield(*x)
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
      v = yield(*x)
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
        return true if yield(*x)
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
        return false unless yield(*x)
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
        return false if yield(*x)
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

  def count(item = (none = true))
    n = 0
    if !none
      each do |*x|
        x = Primitive.zr_enum_value(x)
        n += 1 if Primitive.zr_rb_equal(x, item)
        nil
      end
    elsif block_given?
      each do |*x|
        n += 1 if yield(*x)
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
      break unless yield(*x)

      out << Primitive.zr_enum_value(x)
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
      v = yield(*x)
      v.is_a?(Array) ? out.concat(v) : out << v
      nil
    end
    out
  end

  def collect_concat(&block) = flat_map(&block)

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

  # The count an enumerator reports: the receiver's own, so an endless
  # source answers without being walked. A receiver with no size, or
  # one whose size is unknown, leaves the enumerator's unknown too.
  def enumerable_size
    Primitive.attr! :hidden
    respond_to?(:size) ? size : nil
  end

  def each_cons(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "invalid size" if n <= 0
    return to_enum(:each_cons, n) { (total = enumerable_size) && [total - n + 1, 0].max } unless block_given?

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
    return to_enum(:each_slice, n) { (total = enumerable_size) && (total + n - 1) / n } unless block_given?

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
    return to_enum(:each_entry) { respond_to?(:size) ? size : nil } unless block_given?

    each do |*x|
      x = Primitive.zr_enum_value(x)
      yield x
      nil
    end
    self
  end

  def min_by(n = nil, &block)
    return to_enum(:min_by, n) unless block
    return nmin_run(n, true, false, block, false) unless n.nil?

    best = nil
    key = nil
    first = true
    each do |*x|
      x = Primitive.zr_enum_value(x)
      k = yield(x)
      if first || compared(k, key) < 0
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
    return nmin_run(n, true, true, block, false) unless n.nil?

    best = nil
    key = nil
    first = true
    each do |*x|
      x = Primitive.zr_enum_value(x)
      k = yield(x)
      if first || compared(k, key) > 0
        best = x
        key = k
        first = false
      end
      nil
    end
    best
  end

  # CRuby's rb_nmin_run, behind min(n), max(n), min_by(n) and
  # max_by(n): a buffer of 4n rows that quickselect cuts back to n each
  # time it fills, the last pivot kept as a limit an element must beat
  # to be buffered at all, and the survivors sorted at the end. Among
  # equal keys it is quickselect that picks which rows survive, so this
  # keeps CRuby's choice, not merely its order. A row is the element,
  # or in `by` mode its key and the element.
  def nmin_run(num, by, rev, block, ary)
    Primitive.attr! :hidden
    n = Primitive.zr_index_operand_m(num)
    raise ArgumentError, "negative size (#{n})" if n < 0
    return [] if n == 0
    raise ArgumentError, "too big size" if (((1 << 63) - 1) / 4 / (by ? 2 : 1)) < n

    # OPTIMIZED_CMP, or the block's answer, read as rb_cmpint reads it.
    cmp = lambda do |a, b|
      c = by || block.nil? ? (a <=> b) : block.call(a, b)
      Primitive.zr_cmperr(a, b) if c.nil?
      next c <=> 0 if c.is_a?(Integer)

      c > 0 ? 1 : (c < 0 ? -1 : 0)
    end
    bufmax = n * 4
    buf = []
    curlen = 0
    limit = nil
    limited = false

    filter = lambda do
      next if curlen <= n

      left = 0
      right = curlen - 1
      store_index = 0
      while true
        pivot_index = left + ((right - left) / 2)
        num_pivots = 1
        buf[pivot_index], buf[right] = buf[right], buf[pivot_index]
        pivot_index = right
        store_index = left
        i = left
        while i <= right - num_pivots
          c = cmp.(by ? buf[i][0] : buf[i], by ? buf[pivot_index][0] : buf[pivot_index])
          c = -c if rev
          if c == 0
            buf[i], buf[right - num_pivots] = buf[right - num_pivots], buf[i]
            num_pivots += 1
            next
          end
          if c < 0
            buf[i], buf[store_index] = buf[store_index], buf[i]
            store_index += 1
          end
          i += 1
        end
        j = store_index
        i = right
        while right - num_pivots < i
          break if i <= j

          buf[j], buf[i] = buf[i], buf[j]
          j += 1
          i -= 1
        end
        break if store_index <= n && n <= store_index + num_pivots

        if n < store_index
          right = store_index - 1
        else
          left = store_index + num_pivots
        end
      end
      limit = by ? buf[store_index][0] : buf[store_index]
      limited = true
      curlen = n
      buf.pop(buf.size - n)
    end

    add = lambda do |x|
      cmpv = by ? block.call(x) : x
      if limited
        c = cmp.(cmpv, limit)
        c = -c if rev
        next if c >= 0
      end
      buf << (by ? [cmpv, x] : x)
      curlen += 1
      filter.call if curlen == bufmax
    end

    if ary
      i = 0
      while i < size
        add.call(self[i])
        i += 1
      end
    else
      each do |*x|
        add.call(Primitive.zr_enum_value(x))
        nil
      end
    end
    filter.call
    result = if by
               Primitive.zr_ary_sort_copy(buf, ->(a, b) { cmp.(a[0], b[0]) }).map { |row| row[1] }
             else
               Primitive.zr_ary_sort_copy(buf, ->(a, b) { cmp.(a, b) })
             end
    rev ? result.reverse : result
  end

  def min(n = nil, &blk)
    to_a.min(n, &blk)
  end

  def max(n = nil, &blk)
    to_a.max(n, &blk)
  end

  # One pass, as CRuby makes it: the elements in pairs, each pair
  # ordered once, then its low against the low so far and its high
  # against the high.
  def minmax(&block)
    low = nil
    high = nil
    held = nil
    pending = false
    seen = false
    each do |*x|
      x = Primitive.zr_enum_value(x)
      unless pending
        held = x
        pending = true
        next
      end
      pending = false
      a = held
      b = x
      a, b = b, a if compared(a, b, block) > 0
      if seen
        low = a if compared(a, low, block) < 0
        high = b if compared(b, high, block) > 0
      else
        low = a
        high = b
        seen = true
      end
      nil
    end
    if pending && seen
      low = held if compared(held, low, block) < 0
      high = held if compared(held, high, block) > 0
    elsif pending
      low = held
      high = held
    end
    [low, high]
  end

  # `a <=> b` through `block` when given, refused as CRuby refuses an
  # answer of nil.
  def compared(a, b, block = nil)
    Primitive.attr! :hidden
    c = block ? block.call(a, b) : (a <=> b)
    Primitive.zr_cmperr(a, b) if c.nil?

    c
  end

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
        seen += 1 if yield(*x)
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
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

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
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

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
      return i if block_given? ? yield(*x) : Primitive.zr_rb_equal(Primitive.zr_enum_value(x), v)

      i += 1
      nil
    end
    nil
  end

  def uniq(&block) = to_a.uniq(&block)

  def entries = to_a

  def first(n = (none = true))
    if none
      each do |*x|
        x = Primitive.zr_enum_value(x)
        return x
        nil
      end
      return nil
    end

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

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
      return true if Primitive.zr_rb_equal(x, target)
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

  # Exact while it can be; from the first Float met while the sum is
  # still an Integer or a Rational, Kahan-Babuska compensated, as CRuby's
  # enum_sum adds. A value that is no number ends the compensation: the
  # sum goes on without it, with that value's own `+`.
  def sum(init = 0)
    acc = init
    c = 0.0
    mode = acc.is_a?(Float) ? :float : :exact
    each do |*x|
      v = Primitive.zr_enum_value(x)
      v = yield(v) if block_given?
      if mode == :exact && v.is_a?(Float) && (acc.is_a?(Integer) || acc.is_a?(Rational))
        acc = acc.to_f
        mode = :float
      end
      if mode != :float
        acc += v
      elsif v.is_a?(Float) || v.is_a?(Integer) || v.is_a?(Rational)
        d = v.to_f
        if d.nan? || d.infinite? || acc.nan? || acc.infinite?
          acc += d
        else
          t = acc + d
          c += acc.abs >= d.abs ? (acc - t) + d : (d - t) + acc
          acc = t
        end
      else
        acc += v
        mode = :plain
      end
      nil
    end
    mode == :float ? acc + c : acc
  end
end

module Enumerable
  # Its own body, so an Enumerator made from it names `collect`.
  def collect(&block)
    return to_enum(:collect) unless block

    map(&block)
  end
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

  # The slicing methods stream: each answers an enumerator that reads
  # its source as it runs, so an endless source still gives its first
  # slices.
  def chunk_while(&block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    sliced { |before, x| !block.call(before, x) }
  end

  def slice_when(&block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    sliced { |before, x| block.call(before, x) }
  end

  def slice_before(pattern = nil, &block)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if pattern.nil? && block.nil?

    test = pattern ? ->(x) { pattern === x } : block
    source = self
    Enumerator.new do |y|
      slice = nil
      source.each do |*x|
        x = Primitive.zr_enum_value(x)
        if slice.nil? || test.call(x)
          y << slice if slice
          slice = [x]
        else
          slice << x
        end
        nil
      end
      y << slice if slice
    end
  end

  def slice_after(pattern = nil, &block)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if pattern.nil? && block.nil?

    test = pattern ? ->(x) { pattern === x } : block
    source = self
    Enumerator.new do |y|
      slice = nil
      source.each do |*x|
        x = Primitive.zr_enum_value(x)
        slice = slice ? slice << x : [x]
        if test.call(x)
          y << slice
          slice = nil
        end
        nil
      end
      y << slice if slice
    end
  end

  def chunk
    return to_enum(:chunk) unless block_given?

    source = self
    Enumerator.new do |y|
      key = nil
      slice = nil
      source.each do |*x|
        x = Primitive.zr_enum_value(x)
        k = yield(x)
        if k.nil? || k == :_separator
          y << [key, slice] if slice
          slice = nil
        elsif k == :_alone
          y << [key, slice] if slice
          y << [:_alone, [x]]
          slice = nil
        elsif k.is_a?(Symbol) && k.start_with?("_")
          raise RuntimeError, "symbols beginning with an underscore are reserved"
        elsif slice && key == k
          slice << x
        else
          y << [key, slice] if slice
          key = k
          slice = [x]
        end
        nil
      end
      y << [key, slice] if slice
    end
  end

  # An enumerator of runs, a new run starting where the block says
  # the previous element and this one part.
  def sliced(&part)
    Primitive.attr! :hidden
    source = self
    Enumerator.new do |y|
      slice = nil
      before = nil
      source.each do |*x|
        x = Primitive.zr_enum_value(x)
        if slice.nil?
          slice = [x]
        elsif part.call(before, x)
          y << slice
          slice = [x]
        else
          slice << x
        end
        before = x
        nil
      end
      y << slice if slice
    end
  end

  def chain(*others) = Enumerator::Chain.new(self, *others)

  def lazy = Enumerator::Lazy.from(self)

  # CRuby writes this one in Ruby, so it answers its own parameters.
  def to_set(*args, &block)
    Primitive.attr! :ruby
    Set.new(self, *args, &block)
  end
end
