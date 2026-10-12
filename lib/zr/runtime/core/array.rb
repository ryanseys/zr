# frozen_string_literal: true

# Array over the kernel's storage. CRuby writes these in C, so none
# goes through `each`: a backtrace must not show a row for it.
class Array
  include Enumerable

  # rb_ary_find: the first element that the block accepts, else the
  # value that `ifnone` returns. With no block, the arguments go to the
  # enumerator: the arity check comes after RETURN_ENUMERATOR. Two
  # optional parameters and `given`, the count of arguments, not a rest
  # Array, so a call allocates nothing. A third argument gets the
  # message of the two parameters.
  def find(ifnone = (given = 0; nil), extra = (given ||= 1; nil))
    given ||= 2
    unless block_given?
      return to_enum(__callee__) if given == 0
      return to_enum(__callee__, ifnone) if given == 1

      return to_enum(__callee__, ifnone, extra)
    end
    raise ArgumentError, +"wrong number of arguments (given 2, expected 0..1)" if given == 2

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      element = Primitive.zr_ary_aref1_m(self, i)
      return element if yield(element)

      i += 1
    end
    ifnone&.call
  end
  alias detect find

  # The last element that the block accepts, else the value that
  # `ifnone` returns. With no block, as in find.
  def rfind(ifnone = (given = 0; nil), extra = (given ||= 1; nil))
    given ||= 2
    unless block_given?
      return to_enum(:rfind) if given == 0
      return to_enum(:rfind, ifnone) if given == 1

      return to_enum(:rfind, ifnone, extra)
    end
    raise ArgumentError, +"wrong number of arguments (given 2, expected 0..1)" if given == 2

    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      element = Primitive.zr_ary_aref1_m(self, i)
      return element if yield(element)

      # A shorter array moves the walk to its new end.
      len = Primitive.zr_ary_len_m(self)
      i = len if len < i
      i -= 1
    end
    ifnone&.call
  end

  # rb_ary_any_p and the related methods: how many elements meet the
  # criterion (a pattern's `===`, the block, or truthiness), counted no
  # further than `enough` requires.
  #
  # One optional parameter, not a `*pattern`, and the block reached
  # through a block of this frame's own, not a named block parameter.
  # So a call allocates nothing. A rest Array and a named block's Proc
  # would cost two cells per call, and rb_ary_any_p pays neither. The
  # compiler calls these four 4.9 million times in one cold runtime
  # build.
  def any?(pattern = (bare = true)) = meeting(pattern, bare, block_given?, 1) { |x| yield x }.positive?
  def all?(pattern = (bare = true)) = meeting(pattern, bare, block_given?, 1, negate: true) { |x| yield x }.zero?
  def none?(pattern = (bare = true)) = meeting(pattern, bare, block_given?, 1) { |x| yield x }.zero?
  def one?(pattern = (bare = true)) = meeting(pattern, bare, block_given?, 2) { |x| yield x } == 1

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

  # rb_ary_reverse's copy.
  def reversed
    Primitive.attr! :hidden
    Primitive.zr_ary_reversed(self)
  end

  def last(n = (none = true))
    Primitive.attr! :ruby
    return Primitive.zr_ary_aref1_m(self, -1) if none

    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"negative array size" if n < 0

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
    raise ArgumentError, +"negative array size" if n < 0

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
    # rb_check_array_type: to_ary makes an Array of the other side.
    other = Array.try_convert(other) unless other.is_a?(Array)
    return nil if other.nil?
    return 0 if equal?(other)
    return 0 if Primitive.zr_recursive_enter(self, :<=>)

    begin
      # recursive_cmp: each pair's `<=>` until one is not the fixnum 0,
      # then the lengths, compared natively.
      i = 0
      while i < Primitive.zr_ary_len_m(self) && i < Primitive.zr_ary_len_m(other)
        c = Primitive.zr_ary_aref1_m(self, i) <=> Primitive.zr_ary_aref1_m(other, i)
        return c unless c.equal?(0)

        i += 1
      end
      mine = Primitive.zr_ary_len_m(self)
      theirs = Primitive.zr_ary_len_m(other)
      mine < theirs ? -1 : (mine > theirs ? 1 : 0)
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
    # rb_ary_join_m: a join that falls back to `$,` warns that it did.
    Warning.send(:deprecated, "$, is set to non-nil value") if sep.nil? && !(sep = $,).nil?
    return Primitive.zr_str_usascii(+"") if (Primitive.zr_ary_len_m(self) == 0)

    sep = sep.nil? ? +"" : Primitive.zr_str_operand(sep)
    # rb_ary_join: the first element that is not a String gets its
    # to_str before the join starts, and the join then reads the
    # elements again, as that to_str may change them.
    i = 0
    i += 1 while i < Primitive.zr_ary_len_m(self) && Primitive.zr_ary_aref1_m(self, i).is_a?(String)
    String.try_convert(Primitive.zr_ary_aref1_m(self, i)) if i < Primitive.zr_ary_len_m(self)
    raise ArgumentError, +"recursive array join" if Primitive.zr_recursive_enter(self, :join)

    begin
      s = Primitive.zr_str_usascii(+"")
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        s << sep if i > 0
        x = Primitive.zr_ary_aref1_m(self, i)
        part = join_part(x)
        if part.is_a?(Array)
          s << joined_part(x, part, sep)
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

  # The text of an Array element of `join`. An element that converts
  # to an Array is guarded as itself, as rb_exec_recursive guards the
  # element, so a to_ary that returns a new Array that holds it stops.
  def joined_part(x, part, sep)
    Primitive.attr! :hidden
    return part.join(sep) if part.equal?(x)
    raise ArgumentError, +"recursive array join" if Primitive.zr_recursive_enter(x, :join)

    begin
      part.join(sep)
    ensure
      Primitive.zr_recursive_leave(x, :join)
    end
  end

  # What one element becomes in `join`: its text, or an Array whose
  # elements join in its place.
  def join_part(x)
    Primitive.attr! :hidden
    return x if x.is_a?(String) || x.is_a?(Array)
    # rb_check_string_type, then rb_check_array_type: a nil from either
    # goes on to the next.
    text = String.try_convert(x)
    return text if text

    list = Array.try_convert(x)
    return list if list

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

  def index(v = (omitted = true; nil))
    return to_enum(:index) if omitted && !block_given?

    Primitive.zr_warn_here_m("given block not used") if block_given? && !omitted

    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return i if omitted ? yield(x) : Primitive.zr_rb_equal(x, v)

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

    # ary_min_generic compares the best so far with each element; a
    # block gets each element first.
    best = nil
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      v = Primitive.zr_ary_aref1_m(self, i)
      best = v if i == 0 || (block ? compared(v, best, block) < 0 : compared(best, v) > 0)
      i += 1
    end
    best
  end

  def max(n = nil, &block)
    return nmin_run(n, false, true, block, true) unless n.nil?

    best = nil
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      v = Primitive.zr_ary_aref1_m(self, i)
      best = v if i == 0 || (block ? compared(v, best, block) > 0 : compared(best, v) < 0)
      i += 1
    end
    best
  end

  # BASIC_OP_UNREDEFINED_P for a literal's min or max: whether the
  # program left the core's method in place.
  def self.newarray_optimized?(name)
    Primitive.attr! :hidden
    instance_method(name) == OPTIMIZED[name]
  end

  # vm_opt_newarray_min and _max: a literal's elements, each compared
  # with the best so far.
  def self.newarray_min(items)
    Primitive.attr! :hidden
    best = items[0]
    (1...items.size).each { |i| best = items[i] if items.compared(items[i], best) < 0 }
    best
  end

  def self.newarray_max(items)
    Primitive.attr! :hidden
    best = items[0]
    (1...items.size).each { |i| best = items[i] if items.compared(items[i], best) > 0 }
    best
  end

  # `a <=> b`, or the block's return value, as an Integer; nil fails as
  # ruby's comparison does.
  def compared(a, b, block = nil)
    Primitive.attr! :hidden
    c = block ? block.call(a, b) : (a <=> b)
    Primitive.zr_cmperr(a, b) if c.nil?
    return c if c.is_a?(Integer)

    # rb_cmpint: anything else answers `> 0`, then `< 0`.
    c > 0 ? 1 : (c < 0 ? -1 : 0)
  end

  def rotate!(n = 1)
    n = Primitive.zr_index_operand_m(n)
    replaced(rotated(n))
  end

  def rassoc(value)
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      row = Array.try_convert(Primitive.zr_ary_aref1_m(self, i))
      return row if row && row.size > 1 && Primitive.zr_rb_equal(row[1], value)

      i += 1
    end
    nil
  end

  def bsearch(&block)
    return to_enum(:bsearch) unless block

    at = searched(&block)
    at && Primitive.zr_ary_aref1_m(self, at)
  end

  # Binary search in find-minimum mode (the block returns true or
  # false) or find-any mode (the block returns a number's sign).
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
  def intersection(*others)
    out = Array.new(self)
    others.each { |other| out &= other }
    out
  end

  # rb_ary_union_multi: arrays that are short together are merged by
  # rb_eql, and longer ones through a Hash.
  def union(*others)
    others = others.map { |other| ary_operand(other) }
    if others.sum(Primitive.zr_ary_len_m(self)) { |o| Primitive.zr_ary_len_m(o) } > SMALL_ARRAY_LEN
      out = unique
      others.each { |other| out |= other }
      return out
    end

    out = []
    Array.send(:merge_by_eql, out, self)
    others.each { |other| Array.send(:merge_by_eql, out, other) }
    out
  end

  # rb_ary_difference_multi: each element is checked against each array
  # in turn, by rb_eql, or through a Hash when both sides are long.
  def difference(*others)
    long = Primitive.zr_ary_len_m(self) > SMALL_ARRAY_LEN
    tables = others.map do |other|
      other = ary_operand(other)
      long && Primitive.zr_ary_len_m(other) > SMALL_ARRAY_LEN ? other.to_h { |x| [x, true] } : other
    end
    out = []
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      found = tables.any? { |table| table.is_a?(Hash) ? table.key?(x) : Array.send(:includes_by_eql, table, x) }
      out << x unless found
      i += 1
    end
    out
  end

  # rb_ary_intersect_p: short arrays compare by rb_eql, and longer ones
  # look the longer one's elements up in a Hash of the shorter.
  def intersect?(other)
    other = ary_operand(other)
    return false if Primitive.zr_ary_len_m(self) == 0 || Primitive.zr_ary_len_m(other) == 0

    if Primitive.zr_ary_len_m(self) <= SMALL_ARRAY_LEN && Primitive.zr_ary_len_m(other) <= SMALL_ARRAY_LEN
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        return true if Array.send(:includes_by_eql, other, Primitive.zr_ary_aref1_m(self, i))

        i += 1
      end
      return false
    end
    shorter, longer = Primitive.zr_ary_len_m(self) > Primitive.zr_ary_len_m(other) ? [other, self] : [self, other]
    table = {}
    i = 0
    while i < Primitive.zr_ary_len_m(shorter)
      table[Primitive.zr_ary_aref1_m(shorter, i)] = true
      i += 1
    end
    i = 0
    while i < Primitive.zr_ary_len_m(longer)
      return true if table.key?(Primitive.zr_ary_aref1_m(longer, i))

      i += 1
    end
    false
  end

  def repeated_combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:repeated_combination, k) { k < 0 ? 0 : (k == 0 ? 1 : (Primitive.zr_ary_len_m(self) + k - 1).downto(Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b } / (1..k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && !(Primitive.zr_ary_len_m(self) == 0)
      # rb_ary_repeated_combination walks a private copy when k > 1, so
      # the block can change the receiver.
      reentry_checked("repeated combination") do |check|
        (k == 1 ? self : Array.new(self)).__send__(:pick_repeated, k) { |c| yield c; check.call }
      end
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
      reentry_checked("repeated permute") do |check|
        (k == 1 ? self : Array.new(self)).__send__(:place_repeated, k) { |c| yield c; check.call }
      end
    end
    self
  end

  def combination(k)
    k = Primitive.zr_index_operand_m(k)
    return to_enum(:combination, k) { k < 0 || k > Primitive.zr_ary_len_m(self) ? 0 : (1..Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b } / ((1..k).inject(1) { |a, b| a * b } * (1..Primitive.zr_ary_len_m(self) - k).inject(1) { |a, b| a * b }) } unless block_given?

    if k == 0
      yield []
    elsif k > 0 && k <= Primitive.zr_ary_len_m(self)
      reentry_checked("combination") do |check|
        (k == 1 ? self : Array.new(self)).__send__(:combine, k, 0, []) { |c| yield c; check.call }
      end
    end
    self
  end

  # rb_ary_permutation: with no block, the enumerator comes first, with
  # all the arguments, and its size converts the count
  # (rb_ary_permutation_size). With a block, the arity is 0..1 and nil
  # means the length.
  def permutation(*args)
    unless block_given?
      return to_enum(:permutation, *args) do
        r = args.empty? ? Primitive.zr_ary_len_m(self) : Primitive.zr_index_operand_m(args[0])
        r < 0 || r > Primitive.zr_ary_len_m(self) ? 0 : (Primitive.zr_ary_len_m(self) - r + 1..Primitive.zr_ary_len_m(self)).inject(1) { |a, b| a * b }
      end
    end
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

    k = args[0].nil? ? Primitive.zr_ary_len_m(self) : Primitive.zr_index_operand_m(args[0])

    if k == 0
      yield []
    elsif k > 0 && k <= Primitive.zr_ary_len_m(self)
      reentry_checked("permute") do |check|
        (k == 1 ? self : Array.new(self)).__send__(:permute, k, [], Array.new(Primitive.zr_ary_len_m(self), false)) { |c| yield c; check.call }
      end
    end
    self
  end

  def take(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"attempt to take negative size" if n < 0

    Primitive.zr_ary_aref2_m(self, 0, n)
  end

  # An iterator whose walk keeps state, run with a check that its block
  # calls after each yield: a continuation that brings the block back
  # after the iterator returned raises "<name> reentered", as CRuby's
  # iterators find their hidden Array of state released. The flag is on
  # the heap, which a continuation does not restore.
  def reentry_checked(name)
    Primitive.attr! :hidden
    done = [false]
    yield -> { raise RuntimeError, "#{name} reentered" if done[0] }
  ensure
    done[0] = true if done
  end

  def drop(n)
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"attempt to drop negative size" if n < 0

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
  # makes its own instance, which `Array[...].class` shows, with neither
  # its `initialize` nor its `replace` called (rb_ary_s_create).
  def self.[](*args)
    return args if equal?(Array)

    Primitive.zr_ary_splice(Primitive.zr_class_allocate(self), 0, 0, args)
  end

  def self.try_convert(object)
    return object if Array === object

    converted = Primitive.zr_check_call(object, :to_ary)
    raise TypeError, "can't convert #{conversion_name(object)} to Array (#{conversion_name(object)}#to_ary gives #{conversion_name(converted)})" unless converted.nil? || Array === converted

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

  # The same object counts as found before == is called, so NaN finds
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
    # rb_exec_recursive_paired: only the same pair met again is equal.
    return true if equal?(other) || Primitive.zr_recursive_enter_paired(self, other, :eql?)

    begin
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        return false unless Primitive.zr_rb_eql(Primitive.zr_ary_aref1_m(self, i), Primitive.zr_ary_aref1_m(other, i))

        i += 1
      end
      true
    ensure
      Primitive.zr_recursive_leave(self, :eql?)
    end
  end

  # Elements that hash with no call need no recursion guard
  # (`zr_ary_leaf_hash`, which joins them as this does).
  def hash
    mask = 72057594037927935
    leaf = Primitive.zr_ary_leaf_hash(self, 7)
    return leaf if leaf

    Kernel.send(:outer_hash, self, (Primitive.zr_ary_len_m(self) * 31) + 1) do
      h = 7
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        h = (h * 31 + (Kernel.send(:element_hash, Primitive.zr_ary_aref1_m(self, i)) & mask)) & mask
        i += 1
      end
      h
    end
  end

  # A subclass returns a plain Array.
  def to_a = instance_of?(Array) ? self : Array.new(self)
  # Over the elements themselves, as rb_ary_count walks them: never
  # through `each`, with the length read again each time round.
  def count(item = (none = true))
    return Primitive.zr_ary_len_m(self) if none && !block_given?

    Primitive.zr_warn_here_m("given block not used") if block_given? && !none

    n = 0
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_at_m(self, i)
      n += 1 if none ? yield(x) : Primitive.zr_rb_equal(x, item)
      i += 1
    end
    n
  end

  def append(*vals) = Primitive.zr_ary_splice(self, Primitive.zr_ary_len_m(self), 0, vals)

  # A frozen receiver refuses before the index is read, and an index
  # below `-size - 1` gives no position to insert at.
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
    # rb_ary_replace: the frozen check comes before the conversion.
    Primitive.zr_frozen_error(self) if frozen?
    array = Array.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Array"
    replaced(array)
  end

  # rb_ary_replace with an Array that is already available.
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
      # rb_range_values: an object that answers begin, end and exclude_end?
      # sets as a Range, and an error names the object.
      shown = index
      index = Primitive.zr_range_duck_m(index) || index unless index.is_a?(Integer) || index.is_a?(Range)
      return Primitive.zr_ary_aset_at(self, index, value) unless index.is_a?(Range)

      start, len = range_span(index, shown)
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
    # rb_ary_splice: a start past the end that leaves no room to grow.
    raise IndexError, "index #{start} too big" if start > Primitive.zr_ary_len_m(self) && start >= Primitive.zr_ary_max_size - items.size
    Primitive.zr_ary_splice(self, start, len, items)
    value
  end

  def slice!(start, len = nil)
    Primitive.zr_frozen_error(self) if frozen?
    if len.nil?
      if start.is_a?(Range)
        part = Primitive.zr_ary_aref1_m(self, start)
        return nil if part.nil?

        # rb_range_beg_len: the ends convert with to_int.
        from = start.begin.nil? ? 0 : Primitive.zr_index_operand_m(start.begin)
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

    Primitive.zr_frozen_error(self) if frozen?
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      Primitive.zr_ary_aset_at(self, i, yield(Primitive.zr_ary_aref1_m(self, i)))
      i += 1
    end
    self
  end

  def collect!
    return to_enum(:collect!) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
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



  # Nested Arrays (and the values that `to_ary` returns) spread out
  # `depth` levels. A recursive Array is an error only when the depth is
  # unbounded. A level of 0 flattens nothing, and so does an Array with no
  # element to flatten. In both cases the result is a copy, a plain Array.
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
  # no level, an identity table of the Arrays open on the walk finds
  # one that contains itself. Each element gets at most one to_ary call,
  # as rb_check_array_type makes it. The receiver itself when nothing
  # converts.
  def flattened(level)
    Primitive.attr! :hidden
    # flatten keeps its walk in hidden Arrays: a continuation that brings a
    # to_ary back after the walk ended raises.
    done = [false]
    count = Primitive.zr_ary_len_m(self)
    i = 0
    tmp = nil
    while i < count
      tmp = Array.try_convert(Primitive.zr_ary_at_m(self, i))
      raise RuntimeError, +"flatten reentered" if done[0]
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
        raise RuntimeError, +"flatten reentered" if done[0]
        if tmp.nil?
          result << elt
        else
          if memo
            raise ArgumentError, +"tried to flatten recursive array" if memo[tmp]

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
  ensure
    done[0] = true if done
  end

  def reverse_each
    return to_enum(:reverse_each) { Primitive.zr_ary_len_m(self) } unless block_given?

    # rb_ary_reverse_each: a block that shortens the array moves the
    # walk to the new end.
    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      yield Primitive.zr_ary_aref1_m(self, i)
      len = Primitive.zr_ary_len_m(self)
      i = len if len < i
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
    out = []
    indexes.each do |i|
      next out << Primitive.zr_ary_aref1_m(self, Primitive.zr_index_operand_m(i)) unless i.is_a?(Range)

      # rb_range_beg_len: the ends convert with to_int.
      first = i.begin.nil? ? 0 : Primitive.zr_index_operand_m(i.begin)
      first += Primitive.zr_ary_len_m(self) if first < 0
      raise RangeError, "#{i} out of range" if first < 0

      last = i.end.nil? ? Primitive.zr_ary_len_m(self) - 1 : Primitive.zr_index_operand_m(i.end)
      last += Primitive.zr_ary_len_m(self) if last < 0
      last -= 1 if i.exclude_end? && i.end
      (first..last).each { |j| out << Primitive.zr_ary_aref1_m(self, j) }
    end
    out
  end

  def dig(index, *rest)
    v = Primitive.zr_ary_aref1_m(self, Primitive.zr_index_operand_m(index))
    rest.empty? || v.nil? ? v : Primitive.zr_dig_into(v, rest)
  end

  # Each index fetched; the block gives the value for an index out of bounds.
  def fetch_values(*indexes, &block)
    Primitive.attr! :ruby
    indexes.map { |i| fetched(i, [], &block) }
  end

  def fetch(*args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

    fetched(args.first, args.drop(1), &block)
  end

  # rb_ary_fetch, which fetch_values calls as a function.
  def fetched(index, default)
    Primitive.attr! :hidden

    Primitive.zr_warn_here_m("block supersedes default value argument") if block_given? && !default.empty?
    given = index
    index = Primitive.zr_index_operand_m(index)
    i = index < 0 ? index + Primitive.zr_ary_len_m(self) : index
    return Primitive.zr_ary_aref1_m(self, i) if i >= 0 && i < Primitive.zr_ary_len_m(self)
    return yield(given) if block_given?
    return default[0] unless default.empty?

    raise IndexError, "index #{index} outside of array bounds: #{-Primitive.zr_ary_len_m(self)}...#{Primitive.zr_ary_len_m(self)}"
  end

  def assoc(key)
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      # rb_check_array_type: an element with to_ary counts as its Array.
      x = Array.try_convert(Primitive.zr_ary_aref1_m(self, i))
      return x if x && x.size > 0 && Primitive.zr_rb_equal(x[0], key)

      i += 1
    end
    nil
  end

  def *(other)
    # rb_check_string_type first: to_str joins.
    text = other.is_a?(String) ? other : (other.is_a?(Integer) ? nil : String.try_convert(other))
    return join(text) if text

    other = Primitive.zr_index_operand_m(other)
    raise ArgumentError, +"negative argument" if other < 0
    raise ArgumentError, +"argument too big" if other > 0 && Primitive.zr_ary_max_size / other < Primitive.zr_ary_len_m(self)

    out = []
    other.times { out.concat(self) }
    out
  end

  # rb_ary_diff: a short array on either side compares each pair with
  # rb_eql, and longer ones go through a Hash of the operand.
  def -(other)
    other = ary_operand(other)
    out = []
    small = Primitive.zr_ary_len_m(self) <= SMALL_ARRAY_LEN || Primitive.zr_ary_len_m(other) <= SMALL_ARRAY_LEN
    unless small
      members = {}
      other.each { |x| members[x] = true }
    end
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      out << x unless small ? Array.send(:includes_by_eql, other, x) : members.key?(x)
      i += 1
    end
    out
  end

  # rb_ary_and: short arrays on both sides compare with rb_eql, and
  # longer ones go through a Hash of the operand.
  def &(other)
    other = ary_operand(other)
    return [] if Primitive.zr_ary_len_m(self) == 0 || Primitive.zr_ary_len_m(other) == 0

    if Primitive.zr_ary_len_m(self) <= SMALL_ARRAY_LEN && Primitive.zr_ary_len_m(other) <= SMALL_ARRAY_LEN
      out = []
      i = 0
      while i < Primitive.zr_ary_len_m(self)
        x = Primitive.zr_ary_aref1_m(self, i)
        out << x if Array.send(:includes_by_eql, other, x) && !Array.send(:includes_by_eql, out, x)
        i += 1
      end
      return out
    end
    members = {}
    other.each { |x| members[x] = true }
    unique.select { |x| members.key?(x) }
  end

  # CRuby's SMALL_ARRAY_LEN: up to this length, a set operation walks
  # the array instead of hashing it.
  SMALL_ARRAY_LEN = 16
  private_constant :SMALL_ARRAY_LEN

  # rb_ary_includes_by_eql: `item.eql?` each element, after identity.
  def self.includes_by_eql(ary, item)
    Primitive.attr! :hidden
    i = 0
    while i < Primitive.zr_ary_len_m(ary)
      return true if Primitive.zr_rb_eql(item, Primitive.zr_ary_aref1_m(ary, i))

      i += 1
    end
    false
  end
  private_class_method :includes_by_eql

  # rb_ary_union: each element of `ary` that `out` does not hold yet.
  def self.merge_by_eql(out, ary)
    Primitive.attr! :hidden
    i = 0
    while i < Primitive.zr_ary_len_m(ary)
      x = Primitive.zr_ary_aref1_m(ary, i)
      out << x unless includes_by_eql(out, x)
      i += 1
    end
    out
  end
  private_class_method :merge_by_eql

  # rb_ary_or: short arrays together merge by rb_eql, and longer ones
  # through a Hash.
  def |(other)
    other = ary_operand(other)
    return Array.new(self).concat(other).uniq if Primitive.zr_ary_len_m(self) + Primitive.zr_ary_len_m(other) > SMALL_ARRAY_LEN

    out = []
    Array.send(:merge_by_eql, out, self)
    Array.send(:merge_by_eql, out, other)
    out
  end

  # An operand as CRuby's to_ary() takes one: an Array, or the value of
  # to_ary, else a TypeError that describes it.
  def ary_operand(other)
    Primitive.attr! :hidden
    converted = Array.try_convert(other)
    return converted if converted

    shown = case other
            when nil then +"nil"
            when true then +"true"
            when false then +"false"
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

  # rb_ary_product: the combinations in order, the last array turning
  # fastest. Without a block the result's length comes first, and a
  # length past a long is a RangeError. With a block, each combination
  # goes to it as it is made, however many there are.
  def product(*others)
    arrays = [Array.new(self)]
    i = 0
    while i < others.size
      other = others[i]
      arrays << (Array.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Array")
      i += 1
    end
    total = 1
    i = 0
    while i < arrays.size
      return block_given? ? self : [] if arrays[i].empty?

      total *= arrays[i].size
      raise RangeError, +"too big to product" if total > 0x7fff_ffff_ffff_ffff && !block_given?

      i += 1
    end
    if block_given?
      reentry_checked("product") { |check| product_walk(arrays) { |combo| yield combo; check.call } }
      return self
    end
    result = []
    product_walk(arrays) { |combo| result << combo }
    result
  end

  # The combinations of `arrays`, the last one turning fastest. Returns
  # nil after the last one.
  def product_walk(arrays)
    Primitive.attr! :hidden
    counters = Array.new(arrays.size, 0)
    while true
      combo = Array.new(arrays.size)
      i = 0
      while i < arrays.size
        combo[i] = arrays[i][counters[i]]
        i += 1
      end
      yield combo
      i = arrays.size - 1
      while i >= 0
        counters[i] += 1
        break if counters[i] < arrays[i].size

        counters[i] = 0
        i -= 1
      end
      return if i < 0
    end
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
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1..3)" if args.empty? && !block_given?

    value = block_given? ? nil : args.shift
    raise ArgumentError, "wrong number of arguments (given #{args.size + (block_given? ? 0 : 1)}, expected #{block_given? ? '0..2' : '1..3'})" if args.size > 2

    # rb_ary_fill: a Range alone is a span, its ends converted with
    # to_int; a Range with a length is a start that must be an Integer.
    if args.size == 1 && args[0].is_a?(Range)
      first = args[0].begin.nil? ? 0 : Primitive.zr_index_operand_m(args[0].begin)
      first += Primitive.zr_ary_len_m(self) if first < 0
      raise RangeError, "#{args[0]} out of range" if first < 0

      last = args[0].end.nil? ? Primitive.zr_ary_len_m(self) - 1 : Primitive.zr_index_operand_m(args[0].end)
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
    raise ArgumentError, +"argument too big" if first >= max || len > max - first

    stop = first + len
    # rb_ary_fill sets the new length before the first yield.
    Primitive.zr_ary_aset_at(self, stop - 1, nil) if block_given? && stop > Primitive.zr_ary_len_m(self)
    i = first
    while i < stop
      if block_given?
        # rb_ary_fill stops at a block that shortens the array past i.
        v = yield(i)
        break if i >= Primitive.zr_ary_len_m(self)

        Primitive.zr_ary_aset_at(self, i, v)
      else
        Primitive.zr_ary_aset_at(self, i, value)
      end
      i += 1
    end
    self
  end

  # rb_ary_sort_by_bang: Enumerable#sort_by, which sends `each`, only for
  # two elements or more.
  def sort_by!
    return to_enum(:sort_by!) { Primitive.zr_ary_len_m(self) } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    return self if Primitive.zr_ary_len_m(self) <= 1

    replaced(sort_by { |x| yield(x) })
  end

  def find_index(v = (omitted = true; nil))
    return to_enum(:find_index) if omitted && !block_given?

    Primitive.zr_warn_here_m("given block not used") if block_given? && !omitted
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      x = Primitive.zr_ary_aref1_m(self, i)
      return i if omitted ? yield(x) : Primitive.zr_rb_equal(x, v)

      i += 1
    end
    nil
  end

  def rindex(v = (omitted = true; nil))
    return to_enum(:rindex) if omitted && !block_given?

    Primitive.zr_warn_here_m("given block not used") if block_given? && !omitted

    i = Primitive.zr_ary_len_m(self) - 1
    while i >= 0
      return i if omitted ? yield(Primitive.zr_ary_aref1_m(self, i)) : Primitive.zr_rb_equal(Primitive.zr_ary_aref1_m(self, i), v)

      # rb_ary_rindex: a shorter array moves the walk to its new end.
      len = Primitive.zr_ary_len_m(self)
      if i > len
        break unless omitted

        i = len
      end
      i -= 1
    end
    nil
  end

  def cycle(n = (omitted = true; nil))
    # rb_ary_cycle_size: no rounds, or a count of 0 or less, is 0.
    return to_enum(:cycle, *([n] unless omitted)) { n.nil? ? ((Primitive.zr_ary_len_m(self) == 0) ? 0 : Float::INFINITY) : ((k = Primitive.zr_index_operand_m(n)) <= 0 ? 0 : Primitive.zr_ary_len_m(self) * k) } unless block_given?

    # rb_ary_cycle: each round starts only while the array is not empty,
    # so a block that empties it ends the cycle.
    rounds = n.nil? ? -1 : Primitive.zr_index_operand_m(n)
    return nil if rounds < 0 && !n.nil?

    while Primitive.zr_ary_len_m(self) > 0 && rounds != 0
      rounds -= 1 if rounds > 0
      walked { |x| yield x }
    end
    nil
  end

  def to_h
    h = {}
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      pair = block_given? ? yield(Primitive.zr_ary_aref1_m(self, i)) : Primitive.zr_ary_aref1_m(self, i)
      pair = Array.try_convert(pair) || pair unless pair.is_a?(Array)
      raise TypeError, "wrong element type #{pair.class} at #{i} (expected array)" unless pair.is_a?(Array)
      raise ArgumentError, "wrong array length at #{i} (expected 2, was #{pair.size})" unless pair.size == 2

      h[pair[0]] = pair[1]
      i += 1
    end
    h
  end

  # With a block, the one pass Enumerable makes.
  def minmax = block_given? ? super : [min, max]

  # The core's own min and max, which a literal's fast path stands in for.
  OPTIMIZED = { min: instance_method(:min), max: instance_method(:max) }.freeze
  private_constant :OPTIMIZED
end

class Array
  private

  # `a[seq]` for an ArithmeticSequence, as rb_arithmetic_sequence_beg_len_step
  # bounds it and rb_ary_subseq_step reads it: a stride past 1 in either
  # direction raises where a Range would return nil.
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
    raise ArgumentError, +"slice step cannot be zero" if step.zero?
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

  # How many elements meet the criterion, or with `negate` how many fail
  # it, counted until `enough` do. The criterion is `pattern`'s `===`,
  # unless `bare` says none came; then the caller's block where
  # `by_block` says one came, reached through the block this was given,
  # which yields on; and an element's own truth where neither came. A
  # second pattern is refused by the arity the parameter declares, in
  # rb_ary_any_p's own words.
  def meeting(pattern, bare, by_block, enough, negate: false)
    Primitive.attr! :hidden
    Primitive.zr_warn_here_m("given block not used") if by_block && !bare
    count = 0
    i = 0
    while i < Primitive.zr_ary_len_m(self)
      element = Primitive.zr_ary_aref1_m(self, i)
      met = if !bare then pattern === element
            elsif by_block then yield(element)
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

  # rcombinate0: the indices of each pick never fall, and the last one
  # moves first. A loop, not a recursion, so a long pick needs no stack.
  def pick_repeated(k)
    Primitive.attr! :hidden
    picks = Array.new(k, 0)
    while true
      yield picks.map { |i| Primitive.zr_ary_aref1_m(self, i) }
      i = k - 1
      while i >= 0
        picks[i] += 1
        if picks[i] < Primitive.zr_ary_len_m(self)
          picks.fill(picks[i], i + 1)
          break
        end
        i -= 1
      end
      return if i < 0
    end
  end

  # rpermute0: every index runs through the whole array, the last one
  # first, as the digits of a counter do.
  def place_repeated(k)
    Primitive.attr! :hidden
    places = Array.new(k, 0)
    while true
      yield places.map { |i| Primitive.zr_ary_aref1_m(self, i) }
      i = k - 1
      while i >= 0
        places[i] += 1
        break if places[i] < Primitive.zr_ary_len_m(self)

        places[i] = 0
        i -= 1
      end
      return if i < 0
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
  def range_span(range, shown = range)
    Primitive.attr! :hidden
    start = range.begin.nil? ? 0 : Primitive.zr_index_operand_m(range.begin)
    stop = range.end.nil? ? nil : Primitive.zr_index_operand_m(range.end)

    n = Primitive.zr_ary_len_m(self)
    start += n if start < 0
    raise RangeError, "#{shown.inspect} out of range" if start < 0

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
  # what its `each` yields, sent by name as take_items sends it.
  def zip_column(other, n)
    Primitive.attr! :hidden
    Primitive.attr! :sends_each
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
