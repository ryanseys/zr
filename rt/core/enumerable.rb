# Enumerable over `each`, in the shape CRuby's C implementation has: a
# block passed on to `each`, with what it yields taken as the element,
# packed into an Array when there are several. Each such block answers
# nil, so an `each` that stops on a truthy answer, as `find_index`
# does, sees every element.
module Enumerable
  def map(&blk)
    return to_enum(:map) { enumerable_size } unless blk

    Primitive.zr_enum_collect(self, nil, blk)
  end

  def select
    return to_enum(__callee__) { enumerable_size } unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      out << x if yield(x)
      nil
    end
    out
  end

  def reject
    return to_enum(:reject) { enumerable_size } unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      out << x unless yield(x)
      nil
    end
    out
  end

  def filter_map
    return to_enum(:filter_map) { enumerable_size } unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      v = yield(x)
      out << v if v
      nil
    end
    out
  end

  def find(ifnone = (omitted = true; nil))
    return to_enum(__callee__, *([ifnone] unless omitted)) unless block_given?

    Primitive.zr_enum_each(self, nil) do |x|
      return x if yield(x)
      nil
    end
    ifnone&.call
  end

  def any?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      Primitive.zr_enum_each(self, nil) do |x|
        return true if pattern[0] === x
        nil
      end
    elsif block_given?
      Primitive.zr_enum_each(self, nil) do |x|
        return true if yield(x)
        nil
      end
    else
      Primitive.zr_enum_each(self, nil) do |x|
        return true if x
        nil
      end
    end
    false
  end

  def all?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      Primitive.zr_enum_each(self, nil) do |x|
        return false unless pattern[0] === x
        nil
      end
    elsif block_given?
      Primitive.zr_enum_each(self, nil) do |x|
        return false unless yield(x)
        nil
      end
    else
      Primitive.zr_enum_each(self, nil) do |x|
        return false unless x
        nil
      end
    end
    true
  end

  def none?(*pattern)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    if !pattern.empty?
      Primitive.zr_enum_each(self, nil) do |x|
        return false if pattern[0] === x
        nil
      end
    elsif block_given?
      Primitive.zr_enum_each(self, nil) do |x|
        return false if yield(x)
        nil
      end
    else
      Primitive.zr_enum_each(self, nil) do |x|
        return false if x
        nil
      end
    end
    true
  end

  def count(item = (none = true))
    n = 0
    if !none
      Primitive.zr_enum_each(self, nil) do |x|
        n += 1 if Primitive.zr_rb_equal(x, item)
        nil
      end
    elsif block_given?
      Primitive.zr_enum_each(self, nil) do |x|
        n += 1 if yield(x)
        nil
      end
    else
      Primitive.zr_enum_each(self, nil) do |x|
        n += 1
        nil
      end
    end
    n
  end

  def sort(&blk)
    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      out << x
      nil
    end
    Primitive.zr_ary_sort_copy(out, blk)
  end

  def sort_by
    return to_enum(:sort_by) { enumerable_size } unless block_given?

    pairs = []
    Primitive.zr_enum_each(self, nil) do |x|
      pairs << yield(x) << x
      nil
    end
    Primitive.zr_sort_by(pairs)
  end

  def take_while
    return to_enum(:take_while) unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
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
    Primitive.zr_enum_each(self, nil) do |x|
      dropping = false if dropping && !yield(x)
      out << x unless dropping
      nil
    end
    out
  end

  def each_with_object(memo)
    return to_enum(:each_with_object, memo) { enumerable_size } unless block_given?

    Primitive.zr_enum_each(self, nil) do |x|
      yield(x, memo)
      nil
    end
    memo
  end

  def flat_map
    return to_enum(__callee__) { enumerable_size } unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      v = yield(x)
      v.is_a?(Array) ? out.concat(v) : out << v
      nil
    end
    out
  end

  # Its own body, as CRuby binds both names to one function: a subclass's
  # flat_map is not called, and an Enumerator made from it names
  # `collect_concat`.
  def collect_concat
    return to_enum(:collect_concat) { enumerable_size } unless block_given?

    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      v = yield(x)
      v.is_a?(Array) ? out.concat(v) : out << v
      nil
    end
    out
  end

  def group_by
    return to_enum(:group_by) { enumerable_size } unless block_given?

    out = {}
    Primitive.zr_enum_each(self, nil) do |x|
      k = yield(x)
      (out[k] ||= []) << x
      nil
    end
    out
  end

  def partition
    return to_enum(:partition) { enumerable_size } unless block_given?

    yes = []
    no = []
    Primitive.zr_enum_each(self, nil) do |x|
      (yield(x) ? yes : no) << x
      nil
    end
    [yes, no]
  end

  # The count an enumerator reports: the receiver's own, so an endless
  # source answers without being walked. A receiver with no size, or
  # one whose size is unknown, leaves the enumerator's unknown too.
  # `enum_size` asks with rb_check_funcall, which calls a method the
  # receiver keeps private, and takes whatever it answers as it stands.
  def enumerable_size
    Primitive.attr! :hidden
    respond_to?(:size, true) ? size : nil
  end

  # What a cycle counts: nothing, where the receiver counts nothing or
  # has no count to give; endlessly, where no round was asked for; and
  # otherwise the rounds asked for, none of them being none at all.
  def cycle_size(rounds, endless)
    Primitive.attr! :hidden
    total = enumerable_size
    return total if total.nil? || total == 0
    return Float::INFINITY if endless || rounds.nil?

    rounds = Primitive.zr_index_operand_m(rounds)
    rounds <= 0 ? 0 : total * rounds
  end

  def each_cons(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "invalid size" if n <= 0
    return to_enum(:each_cons, n) { (total = enumerable_size) && [total - n + 1, 0].max } unless block_given?
    # enum_size_over_p: a source that says it is shorter than a window
    # is not walked.
    total = enumerable_size
    return self if total.is_a?(Integer) && total < n

    window = []
    Primitive.zr_enum_each(self, nil) do |x|
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

    # limit_by_enum_size asks the size to reserve a slice's room.
    enumerable_size

    slice = []
    Primitive.zr_enum_each(self, nil) do |x|
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

  def each_entry(*args)
    return to_enum(:each_entry, *args) { enumerable_size } unless block_given?

    Primitive.zr_enum_each(self, args) do |x|
      yield x
      nil
    end
    self
  end

  def min_by(n = (no_count = true; nil), &block)
    return to_enum(:min_by, *([n] unless no_count)) { enumerable_size } unless block
    return nmin_run(n, true, false, block, false) unless n.nil?

    best = nil
    key = nil
    first = true
    Primitive.zr_enum_each(self, nil) do |x|
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

  def max_by(n = (no_count = true; nil), &block)
    return to_enum(:max_by, *([n] unless no_count)) { enumerable_size } unless block
    return nmin_run(n, true, true, block, false) unless n.nil?

    best = nil
    key = nil
    first = true
    Primitive.zr_enum_each(self, nil) do |x|
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
      Primitive.zr_enum_each(self, nil) do |x|
        add.call(x)
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
    elements.min(n, &blk)
  end

  def max(n = nil, &blk)
    elements.max(n, &blk)
  end

  # What `each` yields, gathered as enum_to_a gathers it: a subclass's
  # own `to_a` is not called.
  def elements(*args)
    Primitive.attr! :hidden
    out = []
    Primitive.zr_enum_each(self, args) do |x|
      out << x
      nil
    end
    out
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
    Primitive.zr_enum_each(self, nil) do |x|
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
      Primitive.zr_enum_each(self, nil) do |x|
        seen += 1 if pattern[0] === x
        nil
      end
    elsif block_given?
      Primitive.zr_enum_each(self, nil) do |x|
        seen += 1 if yield(x)
        nil
      end
    else
      Primitive.zr_enum_each(self, nil) do |x|
        seen += 1 if x
        nil
      end
    end
    seen == 1
  end

  def tally(counts = nil)
    unless counts.nil?
      raise TypeError, "no implicit conversion of #{conversion_name(counts)} into Hash" unless counts.is_a?(Hash)
      Primitive.zr_frozen_error(counts) if counts.frozen?

      Primitive.zr_enum_each(self, nil) do |x|
        counts[x] = (counts[x] || 0) + 1
        nil
      end
      return counts
    end
    out = {}
    Primitive.zr_enum_each(self, nil) do |x|
      out[x] = (out[x] || 0) + 1
      nil
    end
    out
  end

  def zip(*others, &block)
    elements.zip(*others, &block)
  end

  def take(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

    out = []
    return out if n == 0

    Primitive.zr_enum_each(self, nil) do |x|
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
    Primitive.zr_enum_each(self, nil) do |x|
      out << x if i >= n
      i += 1
      nil
    end
    out
  end

  def find_index(v = nil)
    return to_enum(:find_index) if v.nil? && !block_given?

    i = 0
    Primitive.zr_enum_each(self, nil) do |x|
      return i if block_given? ? yield(x) : Primitive.zr_rb_equal(x, v)

      i += 1
      nil
    end
    nil
  end

  def uniq(&block) = elements.uniq(&block)

  # `to_a` again, under its own name: a class's own `to_a` does not
  # change it, as CRuby defines both from one function.
  def entries(*args) = elements(*args)

  def first(n = (none = true))
    if none
      Primitive.zr_enum_each(self, nil) do |x|
        return x
        nil
      end
      return nil
    end

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

    out = []
    return out if n == 0

    Primitive.zr_enum_each(self, nil) do |x|
      out << x
      break if out.size >= n
      nil
    end
    out
  end

  def to_a(*args)
    out = []
    Primitive.zr_enum_each(self, args) do |x|
      out << x
      nil
    end
    out
  end

  def include?(target)
    Primitive.zr_enum_each(self, nil) do |x|
      return true if Primitive.zr_rb_equal(x, target)
      nil
    end
    false
  end

  def each_with_index(*args, &block)
    return to_enum(:each_with_index, *args) { enumerable_size } unless block
    # An Array that walks as Array does is walked by index.
    return Primitive.zr_ary_each_with_index_m(self, block) if args.empty? && Primitive.zr_ary_plain_each_p(self)

    i = 0
    Primitive.zr_enum_each(self, args) do |x|
      yield(x, i)
      i += 1
      nil
    end
    self
  end

  def inject(*args, &block) = injected(args, block)

  # inject and reduce, which CRuby defines from one function.
  def injected(args, block)
    Primitive.attr! :hidden
    acc = args.empty? ? nil : args.first
    op = args.size == 2 ? args.last : (args.size == 1 && !block ? args.first : nil)
    if op
      acc = args.size == 2 ? args.first : nil
      first = args.size != 2
      Primitive.zr_enum_each(self, nil) do |x|
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
    Primitive.zr_enum_each(self, nil) do |x|
      if first
        acc = x
        first = false
      else
        acc = block.call(acc, x)
      end
      nil
    end
    acc
  end

  def reduce(*args, &block) = injected(args, block)

  # Exact while it can be; from the first Float met while the sum is
  # still an Integer or a Rational, Kahan-Babuska compensated, as CRuby's
  # enum_sum adds. A value that is no number ends the compensation: the
  # sum goes on without it, with that value's own `+`.
  def sum(init = 0, &block)
    # A Range of Integers adds in closed form, as enum_sum does.
    if !block && !init.is_a?(Float) && is_a?(Range) && self.begin.is_a?(Integer) && self.end.is_a?(Integer)
      last = exclude_end? ? self.end - 1 : self.end
      return last < self.begin ? init : init + (self.begin + last) * (last - self.begin + 1) / 2
    end

    acc = init
    c = 0.0
    mode = acc.is_a?(Float) ? :float : :exact
    Primitive.zr_enum_each(self, nil) do |x|
      v = x
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
  # Its own body, so an Enumerator made from it names `collect`, and a
  # subclass's `map` is not called.
  def collect(&blk)
    return to_enum(:collect) { enumerable_size } unless blk

    Primitive.zr_enum_collect(self, nil, blk)
  end
  alias filter select
  alias find_all select
  alias detect find
  alias member? include?

  def to_h(*args, &block)
    out = {}
    Primitive.zr_enum_each(self, args) do |x|
      pair = x
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
    Primitive.zr_enum_each(self, nil) do |x|
      out << x unless x.nil?
      nil
    end
    out
  end

  def reverse_each(*args, &block)
    return to_enum(:reverse_each, *args) { enumerable_size } unless block

    elements(*args).reverse_each(&block)
    self
  end

  def cycle(n = (endless = true; nil))
    return to_enum(:cycle, *([n] unless endless)) { cycle_size(n, endless) } unless block_given?

    items = elements
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

  # One pass, as enum_minmax_by makes it: the elements in pairs, the
  # pair's keys compared once, then the low against the low so far and
  # the high against the high.
  def minmax_by
    return to_enum(:minmax_by) { enumerable_size } unless block_given?

    min = max = min_key = max_key = last = last_key = nil
    seen = held = false
    Primitive.zr_enum_each(self, nil) do |x|
      key = yield(x)
      unless held
        last = x
        last_key = key
        held = true
        next nil
      end
      held = false
      low, low_key, high, high_key = x, key, last, last_key
      n = compared(last_key, key)
      if n.zero?
        low = high = last
        low_key = high_key = last_key
      elsif n.negative?
        low, low_key, high, high_key = last, last_key, x, key
      end
      if seen
        (min = low; min_key = low_key) if compared(low_key, min_key).negative?
        (max = high; max_key = high_key) if compared(high_key, max_key).positive?
      else
        min, min_key, max, max_key = low, low_key, high, high_key
        seen = true
      end
      nil
    end
    if held
      if seen
        (min = last; min_key = last_key) if compared(last_key, min_key).negative?
        (max = last; max_key = last_key) if compared(last_key, max_key).positive?
      else
        min = max = last
      end
    end
    [min, max]
  end

  def grep(pattern)
    out = []
    Primitive.zr_enum_each(self, nil) do |x|
      if pattern === x
        out << (block_given? ? yield(x) : x)
      end
      nil
    end
    out
  end

  def grep_v(pattern)
    out = []
    Primitive.zr_enum_each(self, nil) do |x|
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
      Primitive.zr_enum_each(source, nil) do |x|
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
      Primitive.zr_enum_each(source, nil) do |x|
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
    return to_enum(:chunk) { enumerable_size } unless block_given?

    source = self
    Enumerator.new do |y|
      key = nil
      slice = nil
      Primitive.zr_enum_each(source, nil) do |x|
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
      Primitive.zr_enum_each(source, nil) do |x|
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
