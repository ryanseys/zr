module Zr::Kern
  # Sorting. ruby's `Array#sort` uses the C library's `qsort_r`, so the
  # order of equal elements comes from that routine. `zr_os_sort` refers to
  # the OS's routine. For macOS, this file has the Bentley-McIlroy
  # algorithm, on records of `stride` bytes whose first word is the Value
  # to compare. It uses indexes in place of pointers. musl's smoothsort is
  # in lib/zr/runtime/kernel/os/linux/smoothsort.rb.
  #
  # The comparator runs Ruby. After a comparison raises, every later
  # comparison returns 0 and runs no Ruby. The sort finishes on its copy,
  # and the pending unwind continues after the sort.
  # `plain` means that Integer and String had the core's own `<=>` when the
  # sort started. Then two fixnums or two Strings compare with no send
  # (zr_sort_plain).
  class Sort < Layout
    attr_accessor :base #: ptr
    attr_accessor :stride #: word
    attr_accessor :blk #: value
    attr_accessor :failed #: word
    attr_accessor :plain #: word
    # The Array that a block sort sorts, frozen while it runs, or nil.
    attr_accessor :owner #: value
  end

  # Converts the result of `x <=> y` to -1, 0 or 1, as CRuby does. For an
  # Integer, it uses the sign. For other values, it tries `> 0`, then
  # `< 0`. nil fails.
  #: (value, value, value) -> value
  def zr_cmpint(r, x, y)
    if zr_fixnum_p(r)
      n = zr_fix2long(r)
      if n > 0
        return zr_fix(1)
      end
      if n < 0
        return zr_fix(0 - 1)
      end
      return zr_fix(0)
    end
    if r == QNIL
      return zr_cmperr(x, y)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, zr_fix(0))
    t = zr_send(r, Machine.id(:>), 1, slot)
    return t if t == QUNDEF
    if t != QNIL && t != QFALSE
      return zr_fix(1)
    end
    t = zr_send(r, Machine.id(:<), 1, slot)
    return t if t == QUNDEF
    if t != QNIL && t != QFALSE
      return zr_fix(0 - 1)
    end
    zr_fix(0)
  end

  # Raises `comparison of X with Y failed: comparator returned nil`, as
  # CRuby's rb_cmpint and ensure_cmp do when `<=>` or an operator gives nil.
  #: (value, value) -> value
  def zr_cmperr(x, y)
    zr_cmperr_reason(x, y, Machine.bytes("comparator returned nil"), 23)
  end

  # The same failure for rb_num_coerce_relop when the operand has no
  # coerce, or its coerce gives nil.
  #: (value, value) -> value
  def zr_cmperr_coerce(x, y)
    zr_cmperr_reason(x, y, Machine.bytes("coercion was not possible"), 25)
  end

  # The same failure for rb_num_compare_with_zero when `x` has no such
  # operator.
  #: (value, value) -> value
  def zr_cmperr_zero(x, y)
    zr_cmperr_reason(x, y, Machine.bytes("unable to compare with zero"), 27)
  end

  # Raises CRuby's rb_cmperr_reason: `comparison of X with Y failed: why`.
  # The message shows Y with inspect when it is a special constant or a
  # Float, and by its class if not.
  #: (value, value, ptr, word) -> value
  def zr_cmperr_reason(x, y, why, len)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("comparison of "), 14)
    zr_buf_class_of(b, x)
    zr_buf_push(b, Machine.bytes(" with "), 6)
    if zr_special_p(y) || zr_float_p(y)
      s = zr_inspect(y)
      return s if s == QUNDEF
      zr_buf_str(b, s)
    else
      zr_buf_class_of(b, y)
    end
    zr_buf_push(b, Machine.bytes(" failed: "), 9)
    zr_buf_push(b, why, len)
    zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end

  #: (ptr, word) -> value
  def zr_sort_at(st, i)
    Machine.value(Machine.load64(Sort[st].base + (i * Sort[st].stride), 0))
  end

  #: (ptr, word, word) -> void
  def zr_sort_swap(st, i, j)
    a = Sort[st].base + (i * Sort[st].stride)
    b = Sort[st].base + (j * Sort[st].stride)
    off = 0
    while off < Sort[st].stride
      t = Machine.load64(a + off, 0)
      Machine.store64(a + off, 0, Machine.load64(b + off, 0))
      Machine.store64(b + off, 0, t)
      off += 8
    end
  end

  #: (ptr, word, word, word) -> void
  def zr_sort_vecswap(st, i, j, n)
    while n > 0
      zr_sort_swap(st, i, j)
      i += 1
      j += 1
      n -= 1
    end
  end

  # Whether `klass` finds the core's own `<=>`: a method entry that the
  # core wrote (MEntry.core). The sort checks this when it starts.
  #: (word) -> bool
  def zr_core_cmp_p(klass)
    e = zr_find_method(zr_global(klass), Machine.id(:<=>))
    e != 0 && MEntry[e].core != 0
  end

  # `a <=> b` with no send, when both are Strings and `a` finds the core's
  # String#<=>, as CRuby's OPTIMIZED_CMP does in Comparable. Returns false
  # for any other pair, and then the caller sends `<=>`.
  #: (value, value) -> value
  def zr_cmp_plain(a, b)
    if zr_special_p(a) || zr_special_p(b) || zr_type(a) != T_STRING || zr_type(b) != T_STRING
      return Machine.value(QFALSE)
    end
    e = zr_find_method(zr_class_of(a), Machine.id(:<=>))
    if e == 0 || MEntry[e].core == 0 || e != zr_find_method(zr_global(G_STRING), Machine.id(:<=>))
      return Machine.value(QFALSE)
    end
    other = Machine.slot(8)
    Machine.store64(other, 0, Machine.word(b))
    zr_str_cmp(a, 1, other, Machine.value(QNIL), Machine.value(QNIL))
  end

  # Whether two fixnums or two Strings compare with no send.
  #: () -> word
  def zr_sort_plain
    zr_core_cmp_p(G_INTEGER) && zr_core_cmp_p(G_STRING) ? 1 : 0
  end

  # Compares the elements at `i` and `j` with the block, or with `<=>`.
  # Two fixnums compare here, with no call, while `zr_sort_cmp_values`
  # would compare them the same way.
  #: (ptr, word, word) -> word
  def zr_sort_cmp(st, i, j)
    x = zr_sort_at(st, i)
    y = zr_sort_at(st, j)
    if zr_fixnum_p(x) && zr_fixnum_p(y) && Sort[st].plain != 0 && Sort[st].blk == QNIL && Sort[st].failed == 0
      return x < y ? 0 - 1 : (x > y ? 1 : 0)
    end
    zr_sort_cmp_values(st, x, y)
  end

  inline :zr_sort_cmp

  # Compares two Values as zr_sort_cmp does: after a failure, 0 and no
  # Ruby.
  #: (ptr, value, value) -> word
  def zr_sort_cmp_values(st, x, y)
    if Sort[st].failed != 0
      return 0
    end
    if Sort[st].blk == QNIL
      if Sort[st].plain != 0
        if zr_fixnum_p(x) && zr_fixnum_p(y)
          return x < y ? 0 - 1 : (x > y ? 1 : 0)
        end
        if !zr_special_p(x) && !zr_special_p(y) && RBasic[x].klass == zr_global(G_STRING) && RBasic[y].klass == zr_global(G_STRING)
          slot = Machine.slot(8)
          Machine.store64(slot, 0, Machine.word(y))
          return zr_fix2long(zr_str_cmp(x, 1, slot, Machine.value(QNIL), Machine.value(QNIL)))
        end
      end
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(y))
      r = zr_send(x, Machine.id(:<=>), 1, slot)
    else
      r = zr_yield2(Sort[st].blk, x, y)
      if r != QUNDEF && (RBasic[Sort[st].owner].flags & FL_FREEZE) == 0
        r = zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("sort reentered"), 14)
      end
    end
    if r != QUNDEF
      r = zr_cmpint(r, x, y)
    end
    if r == QUNDEF
      Sort[st].failed = 1
      return 0
    end
    zr_fix2long(r)
  end

  #: (ptr, word, word, word) -> word
  def zr_sort_med3(st, a, b, c)
    if zr_sort_cmp(st, a, b) < 0
      if zr_sort_cmp(st, b, c) < 0
        return b
      end
      if zr_sort_cmp(st, a, c) < 0
        return c
      end
      return a
    end
    if zr_sort_cmp(st, b, c) > 0
      return b
    end
    if zr_sort_cmp(st, a, c) < 0
      return a
    end
    c
  end

  #: (ptr, word, word) -> void
  def zr_sort_insertion(st, a, n)
    pm = a + 1
    while pm < a + n
      pl = pm
      while pl > a && zr_sort_cmp(st, pl - 1, pl) > 0
        zr_sort_swap(st, pl, pl - 1)
        pl -= 1
      end
      pm += 1
    end
  end

  # Sorts `n` elements from index `a`, in the same order of work as
  # CRuby's mmkubo sort: each split sorts its left part, then its right
  # part. A right part waits on a separate stack, not the machine stack.
  # Thus the sort cannot overflow the stack, even with bad pivots.
  #: (ptr, word, word) -> void
  def zr_sort_range(st, a, n)
    parts = Machine.slot(16)
    waiting = Machine.value(QNIL)
    while true
      left = 0
      if zr_sort_partition(st, a, n, parts)
        left = Machine.load64(parts, 0)
        right = Machine.load64(parts, 8)
        if right > 1
          if waiting == QNIL
            waiting = zr_ary_new(16)
          end
          zr_ary_push(waiting, zr_fix(a + n - right))
          zr_ary_push(waiting, zr_fix(right))
        end
      end
      if left > 1
        n = left
      else
        if waiting == QNIL || RArray[waiting].len == 0
          return
        end
        n = zr_fix2long(zr_ary_at(waiting, RArray[waiting].len - 1))
        a = zr_fix2long(zr_ary_at(waiting, RArray[waiting].len - 2))
        RArray[waiting].len = RArray[waiting].len - 2
      end
    end
  end

  # Splits `n` elements from index `a`. Returns true and writes the sizes
  # of the left part (from `a`) and the right part (to `a + n`) to
  # `parts`. Returns false when the range is already sorted.
  #: (ptr, word, word, ptr) -> bool
  def zr_sort_partition(st, a, n, parts)
    # @type var c: word
    if n < 7
      zr_sort_insertion(st, a, n)
      return false
    end
    swapped = 0
    pm = a + (n / 2)
    if n > 7
      pl = a
      pn = a + n - 1
      if n > 40
        d = n / 8
        pl = zr_sort_med3(st, pl, pl + d, pl + (2 * d))
        pm = zr_sort_med3(st, pm - d, pm, pm + d)
        pn = zr_sort_med3(st, pn - (2 * d), pn - d, pn)
      end
      pm = zr_sort_med3(st, pl, pm, pn)
    end
    zr_sort_swap(st, a, pm)
    pa = a + 1
    pb = a + 1
    pc = a + n - 1
    pd = a + n - 1
    while true
      while pb <= pc
        c = zr_sort_cmp(st, pb, a)
        break if c > 0
        if c == 0
          swapped = 1
          zr_sort_swap(st, pa, pb)
          pa += 1
        end
        pb += 1
      end
      while pb <= pc
        c = zr_sort_cmp(st, pc, a)
        break if c < 0
        if c == 0
          swapped = 1
          zr_sort_swap(st, pc, pd)
          pd -= 1
        end
        pc -= 1
      end
      break if pb > pc
      zr_sort_swap(st, pb, pc)
      swapped = 1
      pb += 1
      pc -= 1
    end
    if swapped == 0
      zr_sort_insertion(st, a, n)
      return false
    end
    pn = a + n
    r = pa - a
    if pb - pa < r
      r = pb - pa
    end
    zr_sort_vecswap(st, a, pb - r, r)
    r = pd - pc
    if pn - pd - 1 < r
      r = pn - pd - 1
    end
    zr_sort_vecswap(st, pb, pn - r, r)
    Machine.store64(parts, 0, pb - pa)
    Machine.store64(parts, 8, pd - pc)
    true
  end

  # Apple Libc-1752's qsort_r (stdlib/FreeBSD/qsort.c), which darwin's
  # ruby calls: an insertion sort for 7 elements or fewer, else a split
  # around the pseudomedian. A split that swaps nothing tries an insertion
  # sort with a limit of 1 + n / 4 swaps, and goes on from where it
  # stopped if that is not enough. The smaller part is sorted first, and
  # past a depth of 2 * floor(log2 n) splits, heapsort finishes the range.
  #: (ptr, word) -> void
  def zr_sort_apple_all(st, n)
    depth = 0
    m = n
    while m > 1
      depth += 2
      m = m / 2
    end
    zr_sort_apple(st, 0, n, depth)
  end

  #: (ptr, word, word, word) -> void
  def zr_sort_apple(st, a, n, depth)
    # @type var c: word
    while true
      if depth <= 0
        zr_sort_heap(st, a, n)
        return
      end
      depth -= 1
      if n <= 7
        zr_sort_isort(st, a, n, 0)
        return
      end
      pl = a
      pm = a + (n / 2)
      pn = a + n - 1
      if n > 40
        d = n / 8
        pl = zr_sort_med3(st, pl, pl + d, pl + (2 * d))
        pm = zr_sort_med3(st, pm - d, pm, pm + d)
        pn = zr_sort_med3(st, pn - (2 * d), pn - d, pn)
      end
      pm = zr_sort_med3(st, pl, pm, pn)
      zr_sort_swap(st, a, pm)
      swapped = 0
      pa = a + 1
      pb = a + 1
      pc = a + n - 1
      pd = a + n - 1
      while true
        while pb <= pc
          c = zr_sort_cmp(st, pb, a)
          break if c > 0
          if c == 0
            swapped = 1
            zr_sort_swap(st, pa, pb)
            pa += 1
          end
          pb += 1
        end
        while pb <= pc
          c = zr_sort_cmp(st, pc, a)
          break if c < 0
          if c == 0
            swapped = 1
            zr_sort_swap(st, pc, pd)
            pd -= 1
          end
          pc -= 1
        end
        break if pb > pc
        zr_sort_swap(st, pb, pc)
        swapped = 1
        pb += 1
        pc -= 1
      end
      pn = a + n
      r = pa - a
      if pb - pa < r
        r = pb - pa
      end
      zr_sort_vecswap(st, a, pb - r, r)
      r = pd - pc
      if pn - pd - 1 < r
        r = pn - pd - 1
      end
      zr_sort_vecswap(st, pb, pn - r, r)
      if swapped == 0 && zr_sort_isort(st, a, n, 1 + (n / 4))
        return
      end
      d1 = pb - pa
      d2 = pd - pc
      if d1 <= d2
        if d1 > 1
          zr_sort_apple(st, a, d1, depth)
        end
        if d2 <= 1
          return
        end
        a = pn - d2
        n = d2
      else
        if d2 > 1
          zr_sort_apple(st, pn - d2, d2, depth)
        end
        if d1 <= 1
          return
        end
        n = d1
      end
    end
  end

  # _isort: an insertion sort that stops, returning false, after `limit`
  # swaps when `limit` is not 0.
  #: (ptr, word, word, word) -> bool
  def zr_sort_isort(st, a, n, limit)
    count = 0
    pm = a + 1
    while pm < a + n
      pl = pm
      while pl > a && zr_sort_cmp(st, pl - 1, pl) > 0
        zr_sort_swap(st, pl, pl - 1)
        if limit != 0
          count += 1
          if count > limit
            return false
          end
        end
        pl -= 1
      end
      pm += 1
    end
    true
  end

  # The address of element `i` (from 1) of the `n` elements at `a`, as
  # heapsort numbers them.
  #: (ptr, word, word) -> ptr
  def zr_sort_heap_at(st, a, i)
    Sort[st].base + ((a + i - 1) * Sort[st].stride)
  end

  # heapsort (stdlib/FreeBSD/heapsort.c): build the heap, then move the
  # top to the end and sift the displaced element back in. The displaced
  # element waits in an Array, where the collector sees it while the block
  # runs.
  #: (ptr, word, word) -> void
  def zr_sort_heap(st, a, n)
    # @type var par: word
    # @type var child: word
    if n <= 1
      return
    end
    stride = Sort[st].stride
    keep = zr_ary_new(2)
    zr_ary_push(keep, Machine.value(QNIL))
    zr_ary_push(keep, Machine.value(QNIL))
    k = RArray[keep].ptr
    l = n / 2
    while l > 0
      par = l
      child = par * 2
      while child <= n
        if child < n && zr_sort_cmp(st, a + child - 1, a + child) < 0
          child += 1
        end
        if zr_sort_cmp(st, a + child - 1, a + par - 1) <= 0
          break
        end
        zr_sort_swap(st, a + par - 1, a + child - 1)
        par = child
        child = par * 2
      end
      l -= 1
    end
    while n > 1
      zr_memcpy(k, zr_sort_heap_at(st, a, n), stride)
      zr_memcpy(zr_sort_heap_at(st, a, n), zr_sort_heap_at(st, a, 1), stride)
      n -= 1
      par = 1
      child = 2
      while child <= n
        if child < n && zr_sort_cmp(st, a + child - 1, a + child) < 0
          child += 1
        end
        zr_memcpy(zr_sort_heap_at(st, a, par), zr_sort_heap_at(st, a, child), stride)
        par = child
        child = par * 2
      end
      while true
        child = par
        par = child / 2
        if child == 1 || zr_sort_cmp_values(st, Machine.value(Machine.load64(k, 0)), zr_sort_at(st, a + par - 1)) < 0
          zr_memcpy(zr_sort_heap_at(st, a, child), k, stride)
          break
        end
        zr_memcpy(zr_sort_heap_at(st, a, child), zr_sort_heap_at(st, a, par), stride)
      end
    end
    RArray[keep].len = 0
  end

  # Sorts `ary` in place. `ary` is a copy that the caller made. Thus a
  # comparison that raises does not change the original, and the copy
  # keeps every element reachable while the block runs.
  #: (value, value) -> value
  def zr_ary_sort_copy(ary, blk)
    n = RArray[ary].len
    if n < 2
      return ary
    end
    st = Machine.slot(Sort.size)
    Sort[st].base = RArray[ary].ptr
    Sort[st].stride = 8
    Sort[st].blk = blk
    Sort[st].failed = 0
    Sort[st].plain = blk == QNIL ? zr_sort_plain() : 0
    # The copy that a block sorts is frozen while the sort runs, as CRuby
    # hides its sort's temporary Array. A continuation that a block took
    # can enter a comparison again after the sort returned; the copy is
    # not frozen then, and the comparison raises (sort_reentered).
    Sort[st].owner = blk == QNIL ? Machine.value(QNIL) : ary
    RBasic[ary].flags = RBasic[ary].flags | FL_FREEZE
    zr_os_sort(st, n)
    RBasic[ary].flags = RBasic[ary].flags & (0 - FL_FREEZE - 1)
    if Sort[st].failed != 0
      return Machine.value(QUNDEF)
    end
    ary
  end

  #: (value, word, ptr, value, value) -> value
  def zr_ary_sort(recv, argc, argv, cref, blk)
    zr_ary_sort_copy(zr_ary_of(RArray[recv].len, RArray[recv].ptr), blk)
  end

  # Copies the elements and the length of the sorted copy back to the
  # receiver. As in CRuby, changes that a block made to the receiver
  # during the sort are lost.
  #: (value, word, ptr, value, value) -> value
  def zr_ary_sort_bang(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    tmp = zr_ary_sort_copy(zr_ary_of(RArray[recv].len, RArray[recv].ptr), blk)
    return tmp if tmp == QUNDEF
    # sort_returned: a comparison that froze the Array leaves it as it
    # is. CRuby checks after each comparison; the copy is what changes.
    if zr_modify_frozen_p(recv)
      return zr_raise_msg(zr_global(G_FROZEN_ERROR), Machine.bytes("array frozen during sort"), 24)
    end
    n = RArray[tmp].len
    zr_ary_reserve(recv, n)
    zr_memcpy(RArray[recv].ptr, RArray[tmp].ptr, n * 8)
    zr_write_barrier_all(recv)
    RArray[recv].len = n
    recv
  end

  # The records of `sort_by`: a key and its element, in an Array of
  # pairs. When every key is a fixnum or a Float, CRuby sorts with its own
  # introsort in place of `qsort_r`, and the order of equal keys comes from
  # that routine.
  class Pair < Layout
    attr_accessor :key #: value
    attr_accessor :elem #: value
  end

  # The first two keys that a uniform sort cannot compare (a NaN). The
  # sort keeps them until it has put every record back, because the error
  # message allocates, and a record that is moving is only in a scratch
  # slot that the collector does not see. Until then, every comparison
  # returns that neither key is less.
  #: () -> ptr
  def zr_uniform_failed
    Machine.static(:uniform_failed, 24)
  end

  # `x <=> y` for a Float `x` and a fixnum or Float `y`, as in
  # rb_float_cmp. A NaN is recorded as the failure and returns 0.
  #: (value, value) -> word
  def zr_uniform_float_cmp(x, y)
    st = zr_uniform_failed()
    if Machine.load64(st, 0) != 0
      return 0
    end
    c = zr_float_cmp_value(x, y)
    if c == 2
      Machine.store64(st, 0, 1)
      Machine.store64(st, 8, Machine.word(x))
      Machine.store64(st, 16, Machine.word(y))
      return 0
    end
    c
  end

  # rb_uniform_is_less: compares two fixnums by their words. If not, it
  # compares with the Float operand first, as CRuby does.
  #: (value, value) -> bool
  def zr_uniform_key_less(a, b)
    if zr_fixnum_p(a) && zr_fixnum_p(b)
      return Machine.sword(a) < Machine.sword(b)
    end
    zr_uniform_float_less(a, b)
  end
  # In each loop of the sort, so two fixnums compare with no call.
  inline :zr_uniform_key_less

  # rb_uniform_is_less when a key is a Float.
  #: (value, value) -> bool
  def zr_uniform_float_less(a, b)
    if zr_fixnum_p(a)
      return zr_uniform_float_cmp(b, a) > 0
    end
    zr_uniform_float_cmp(a, b) < 0
  end

  # rb_uniform_is_larger, for the check for an input that is already in
  # order.
  #: (value, value) -> bool
  def zr_uniform_key_larger(a, b)
    if zr_fixnum_p(a) && zr_fixnum_p(b)
      return Machine.sword(a) > Machine.sword(b)
    end
    if zr_fixnum_p(a)
      return zr_uniform_float_cmp(b, a) < 0
    end
    zr_uniform_float_cmp(a, b) > 0
  end

  #: (ptr, word, word) -> bool
  def zr_uniform_less(base, i, j)
    zr_uniform_key_less(Pair[base + (i * Pair.size)].key, Pair[base + (j * Pair.size)].key)
  end

  inline :zr_uniform_less

  #: (ptr, word, word) -> void
  def zr_uniform_swap(base, i, j)
    a = base + (i * Pair.size)
    b = base + (j * Pair.size)
    k = Pair[a].key
    e = Pair[a].elem
    Pair[a].key = Pair[b].key
    Pair[a].elem = Pair[b].elem
    Pair[b].key = k
    Pair[b].elem = e
  end

  # Moves the record at `i` to `pos`, and shifts the records between them
  # up by one.
  #: (ptr, word, word) -> void
  def zr_uniform_move(base, i, pos)
    k = Pair[base + (i * Pair.size)].key
    e = Pair[base + (i * Pair.size)].elem
    while i > pos
      Pair[base + (i * Pair.size)].key = Pair[base + ((i - 1) * Pair.size)].key
      Pair[base + (i * Pair.size)].elem = Pair[base + ((i - 1) * Pair.size)].elem
      i -= 1
    end
    Pair[base + (pos * Pair.size)].key = k
    Pair[base + (pos * Pair.size)].elem = e
  end

  #: (ptr, word, word) -> void
  def zr_uniform_insertion(base, a, stop)
    index = a + 1
    while index < stop
      if zr_uniform_less(base, index, a)
        zr_uniform_move(base, index, a)
      else
        k = index
        while zr_uniform_less(base, index, k - 1)
          k -= 1
        end
        zr_uniform_move(base, index, k)
      end
      index += 1
    end
  end

  # Sifts `offset` down in the heap at `a`. The heap ends at `a + len`.
  #: (ptr, word, word, word) -> void
  def zr_uniform_heap_down(base, a, offset, len)
    scratch = Machine.slot(Pair.size)
    Pair[scratch].key = Pair[base + ((a + offset) * Pair.size)].key
    Pair[scratch].elem = Pair[base + ((a + offset) * Pair.size)].elem
    while true
      c = (offset * 2) + 1
      break if c > len
      if c < len && zr_uniform_less(base, a + c, a + c + 1)
        c += 1
      end
      if !zr_uniform_key_less(Pair[scratch].key, Pair[base + ((a + c) * Pair.size)].key)
        break
      end
      Pair[base + ((a + offset) * Pair.size)].key = Pair[base + ((a + c) * Pair.size)].key
      Pair[base + ((a + offset) * Pair.size)].elem = Pair[base + ((a + c) * Pair.size)].elem
      offset = c
    end
    Pair[base + ((a + offset) * Pair.size)].key = Pair[scratch].key
    Pair[base + ((a + offset) * Pair.size)].elem = Pair[scratch].elem
  end

  #: (ptr, word, word) -> void
  def zr_uniform_heapsort(base, a, stop)
    n = stop - a
    if n < 2
      return
    end
    offset = n / 2
    while offset > 0
      offset -= 1
      zr_uniform_heap_down(base, a, offset, n - 1)
    end
    offset = n - 1
    while offset > 0
      zr_uniform_swap(base, a, a + offset)
      offset -= 1
      zr_uniform_heap_down(base, a, 0, offset)
    end
  end

  # Returns the pivot key: the median of three records.
  #: (ptr, word, word, word) -> value
  def zr_uniform_med3(base, a, b, c)
    if zr_uniform_less(base, a, b)
      if zr_uniform_less(base, b, c)
        return Pair[base + (b * Pair.size)].key
      end
      if zr_uniform_less(base, c, a)
        return Pair[base + (a * Pair.size)].key
      end
      return Pair[base + (c * Pair.size)].key
    end
    if zr_uniform_less(base, c, b)
      return Pair[base + (b * Pair.size)].key
    end
    if zr_uniform_less(base, a, c)
      return Pair[base + (a * Pair.size)].key
    end
    Pair[base + (c * Pair.size)].key
  end

  #: (ptr, word, word, word) -> void
  def zr_uniform_quicksort(base, a, stop, d)
    if stop - a <= 16
      zr_uniform_insertion(base, a, stop)
      return
    end
    if d == 0
      zr_uniform_heapsort(base, a, stop)
      return
    end
    x = zr_uniform_med3(base, a, a + ((stop - a) / 2), stop - 1)
    i = a
    j = stop - 1
    while true
      while zr_uniform_key_less(Pair[base + (i * Pair.size)].key, x)
        i += 1
      end
      while zr_uniform_key_less(x, Pair[base + (j * Pair.size)].key)
        j -= 1
      end
      if i <= j
        zr_uniform_swap(base, i, j)
        i += 1
        j -= 1
      end
      break if i > j
    end
    j += 1
    if stop - j > 1
      zr_uniform_quicksort(base, j, stop, d - 1)
    end
    if i - a > 1
      zr_uniform_quicksort(base, a, i, d - 1)
    end
  end

  # Records that are already in order stay as they are. If not, it runs
  # an introsort with a depth limit of twice the bit length of `n`.
  #: (ptr, word) -> void
  def zr_uniform_sort(base, n)
    i = 1
    sorted = 1
    while i < n
      if zr_uniform_key_larger(Pair[base + ((i - 1) * Pair.size)].key, Pair[base + (i * Pair.size)].key)
        sorted = 0
        break
      end
      i += 1
    end
    if sorted != 0
      return
    end
    d = 0
    m = n
    while m > 1
      m = m / 2
      d += 1
    end
    zr_uniform_quicksort(base, 0, n, d * 2)
  end

  # `pairs` contains a key, then its element, for each pair. Returns the
  # elements in key order, or `undef` when a comparison raised.
  #: (value) -> value
  def zr_sort_by(pairs)
    n = RArray[pairs].len / 2
    base = RArray[pairs].ptr
    # enum.c sorts the keys natively only while Integer and Float have the
    # core's own `<=>`.
    uniform = zr_core_cmp_p(G_INTEGER) && zr_core_cmp_p(G_FLOAT) ? 1 : 0
    i = 0
    while i < n
      k = Pair[base + (i * Pair.size)].key
      if !zr_fixnum_p(k) && !zr_float_p(k)
        uniform = 0
      end
      i += 1
    end
    if uniform != 0
      st = zr_uniform_failed()
      Machine.store64(st, 0, 0)
      zr_uniform_sort(base, n)
      if Machine.load64(st, 0) != 0
        Machine.store64(st, 0, 0)
        return zr_cmperr(Machine.value(Machine.load64(st, 8)), Machine.value(Machine.load64(st, 16)))
      end
    else
      st = Machine.slot(Sort.size)
      Sort[st].base = base
      Sort[st].stride = Pair.size
      Sort[st].blk = Machine.value(QNIL)
      Sort[st].failed = 0
      Sort[st].plain = zr_sort_plain()
      Sort[st].owner = Machine.value(QNIL)
      zr_os_sort(st, n)
      if Sort[st].failed != 0
        return Machine.value(QUNDEF)
      end
    end
    out = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(out, Pair[RArray[pairs].ptr + (i * Pair.size)].elem)
      i += 1
    end
    out
  end
end
