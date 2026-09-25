# Sorting. ruby's `Array#sort` uses the C library's `qsort_r`, so the
# order of equal elements comes from that routine. `zr_os_sort` refers to
# the OS's routine. For macOS, this file has the Bentley-McIlroy
# algorithm, on records of `stride` bytes whose first word is the Value
# to compare. It uses indexes in place of pointers. musl's smoothsort is
# in runtime/kernel/os/linux/smoothsort.rb.
#
# The comparator runs Ruby. After a comparison raises, every later
# comparison returns 0 and runs no Ruby. The sort finishes on its copy,
# and the pending unwind continues after the sort.
# `plain` means that Integer and String had the core's own `<=>` when the
# sort started. Then two fixnums or two Strings compare with no send
# (zr_sort_plain).
Machine.struct :Sort, base: Ptr, stride: Word, blk: Value, failed: Word, plain: Word

# Converts the result of `x <=> y` to -1, 0 or 1, as CRuby does. For an
# Integer, it uses the sign. For other values, it tries `> 0`, then
# `< 0`. nil fails.
sig [Value, Value, Value] => Value
machine def zr_cmpint(r, x, y)
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

# Raises `comparison of X with Y failed`. The message shows Y with
# inspect when it is a special constant, and by its class if not.
sig [Value, Value] => Value
machine def zr_cmperr(x, y)
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
  zr_buf_push(b, Machine.bytes(" failed"), 7)
  zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
end

sig [Ptr, Word] => Value
machine def zr_sort_at(st, i)
  Machine.value(Machine.load64(Sort.base(st) + (i * Sort.stride(st)), 0))
end

sig [Ptr, Word, Word] => Void
machine def zr_sort_swap(st, i, j)
  a = Sort.base(st) + (i * Sort.stride(st))
  b = Sort.base(st) + (j * Sort.stride(st))
  off = 0
  while off < Sort.stride(st)
    t = Machine.load64(a + off, 0)
    Machine.store64(a + off, 0, Machine.load64(b + off, 0))
    Machine.store64(b + off, 0, t)
    off += 8
  end
end

sig [Ptr, Word, Word, Word] => Void
machine def zr_sort_vecswap(st, i, j, n)
  while n > 0
    zr_sort_swap(st, i, j)
    i += 1
    j += 1
    n -= 1
  end
end

# Whether `klass` finds the core's own `<=>`: a method entry that the
# core wrote (MEntry.core). The sort checks this when it starts.
sig [Word] => Bool
machine def zr_core_cmp_p(klass)
  e = zr_find_method(zr_global(klass), Machine.id(:<=>))
  e != 0 && MEntry.core(e) != 0
end

# `a <=> b` with no send, when both are Strings and `a` finds the core's
# String#<=>, as CRuby's OPTIMIZED_CMP does in Comparable. Returns false
# for any other pair, and then the caller sends `<=>`.
sig [Value, Value] => Value
machine def zr_cmp_plain(a, b)
  if zr_special_p(a) || zr_special_p(b) || zr_type(a) != T_STRING || zr_type(b) != T_STRING
    return Machine.value(QFALSE)
  end
  e = zr_find_method(zr_class_of(a), Machine.id(:<=>))
  if e == 0 || MEntry.core(e) == 0 || e != zr_find_method(zr_global(G_STRING), Machine.id(:<=>))
    return Machine.value(QFALSE)
  end
  other = Machine.slot(8)
  Machine.store64(other, 0, Machine.word(b))
  zr_str_cmp(a, 1, other, Machine.value(QNIL), Machine.value(QNIL))
end

# Whether two fixnums or two Strings compare with no send.
sig [] => Word
machine def zr_sort_plain
  zr_core_cmp_p(G_INTEGER) && zr_core_cmp_p(G_STRING) ? 1 : 0
end

# Compares the elements at `i` and `j` with the block, or with `<=>`.
sig [Ptr, Word, Word] => Word
machine def zr_sort_cmp(st, i, j)
  zr_sort_cmp_values(st, zr_sort_at(st, i), zr_sort_at(st, j))
end

# Compares two Values as zr_sort_cmp does: after a failure, 0 and no
# Ruby.
sig [Ptr, Value, Value] => Word
machine def zr_sort_cmp_values(st, x, y)
  if Sort.failed(st) != 0
    return 0
  end
  if Sort.blk(st) == QNIL
    if Sort.plain(st) != 0
      if zr_fixnum_p(x) && zr_fixnum_p(y)
        return x < y ? 0 - 1 : (x > y ? 1 : 0)
      end
      if !zr_special_p(x) && !zr_special_p(y) && RBasic.klass(x) == zr_global(G_STRING) && RBasic.klass(y) == zr_global(G_STRING)
        slot = Machine.slot(8)
        Machine.store64(slot, 0, Machine.word(y))
        return zr_fix2long(zr_str_cmp(x, 1, slot, Machine.value(QNIL), Machine.value(QNIL)))
      end
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(y))
    r = zr_send(x, Machine.id(:<=>), 1, slot)
  else
    r = zr_yield2(Sort.blk(st), x, y)
  end
  if r != QUNDEF
    r = zr_cmpint(r, x, y)
  end
  if r == QUNDEF
    Sort.set_failed(st, 1)
    return 0
  end
  zr_fix2long(r)
end

sig [Ptr, Word, Word, Word] => Word
machine def zr_sort_med3(st, a, b, c)
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

sig [Ptr, Word, Word] => Void
machine def zr_sort_insertion(st, a, n)
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
sig [Ptr, Word, Word] => Void
machine def zr_sort_range(st, a, n)
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
      if waiting == QNIL || RArray.len(waiting) == 0
        return
      end
      n = zr_fix2long(zr_ary_at(waiting, RArray.len(waiting) - 1))
      a = zr_fix2long(zr_ary_at(waiting, RArray.len(waiting) - 2))
      RArray.set_len(waiting, RArray.len(waiting) - 2)
    end
  end
end

# Splits `n` elements from index `a`. Returns true and writes the sizes
# of the left part (from `a`) and the right part (to `a + n`) to
# `parts`. Returns false when the range is already sorted.
sig [Ptr, Word, Word, Ptr] => Bool
machine def zr_sort_partition(st, a, n, parts)
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
sig [Ptr, Word] => Void
machine def zr_sort_apple_all(st, n)
  depth = 0
  m = n
  while m > 1
    depth += 2
    m = m / 2
  end
  zr_sort_apple(st, 0, n, depth)
end

sig [Ptr, Word, Word, Word] => Void
machine def zr_sort_apple(st, a, n, depth)
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
sig [Ptr, Word, Word, Word] => Bool
machine def zr_sort_isort(st, a, n, limit)
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
sig [Ptr, Word, Word] => Ptr
machine def zr_sort_heap_at(st, a, i)
  Sort.base(st) + ((a + i - 1) * Sort.stride(st))
end

# heapsort (stdlib/FreeBSD/heapsort.c): build the heap, then move the
# top to the end and sift the displaced element back in. The displaced
# element waits in an Array, where the collector sees it while the block
# runs.
sig [Ptr, Word, Word] => Void
machine def zr_sort_heap(st, a, n)
  if n <= 1
    return
  end
  stride = Sort.stride(st)
  keep = zr_ary_new(2)
  zr_ary_push(keep, Machine.value(QNIL))
  zr_ary_push(keep, Machine.value(QNIL))
  k = RArray.ptr(keep)
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
  RArray.set_len(keep, 0)
end

# Sorts `ary` in place. `ary` is a copy that the caller made. Thus a
# comparison that raises does not change the original, and the copy
# keeps every element reachable while the block runs.
sig [Value, Value] => Value
machine def zr_ary_sort_copy(ary, blk)
  n = RArray.len(ary)
  if n < 2
    return ary
  end
  st = Machine.slot(Sort.size)
  Sort.set_base(st, RArray.ptr(ary))
  Sort.set_stride(st, 8)
  Sort.set_blk(st, blk)
  Sort.set_failed(st, 0)
  Sort.set_plain(st, blk == QNIL ? zr_sort_plain() : 0)
  zr_os_sort(st, n)
  if Sort.failed(st) != 0
    return Machine.value(QUNDEF)
  end
  ary
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_sort(recv, argc, argv, cref, blk)
  zr_ary_sort_copy(zr_ary_of(RArray.len(recv), RArray.ptr(recv)), blk)
end

# Copies the elements and the length of the sorted copy back to the
# receiver. As in CRuby, changes that a block made to the receiver
# during the sort are lost.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_sort_bang(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  tmp = zr_ary_sort_copy(zr_ary_of(RArray.len(recv), RArray.ptr(recv)), blk)
  return tmp if tmp == QUNDEF
  n = RArray.len(tmp)
  zr_ary_reserve(recv, n)
  zr_memcpy(RArray.ptr(recv), RArray.ptr(tmp), n * 8)
  zr_write_barrier_all(recv)
  RArray.set_len(recv, n)
  recv
end

# The records of `sort_by`: a key and its element, in an Array of
# pairs. When every key is a fixnum or a Float, CRuby sorts with its own
# introsort in place of `qsort_r`, and the order of equal keys comes from
# that routine.
Machine.struct :Pair, key: Value, elem: Value

# The first two keys that a uniform sort cannot compare (a NaN). The
# sort keeps them until it has put every record back, because the error
# message allocates, and a record that is moving is only in a scratch
# slot that the collector does not see. Until then, every comparison
# returns that neither key is less.
sig [] => Ptr
machine def zr_uniform_failed
  Machine.static(:uniform_failed, 24)
end

# `x <=> y` for a Float `x` and a fixnum or Float `y`, as in
# rb_float_cmp. A NaN is recorded as the failure and returns 0.
sig [Value, Value] => Word
machine def zr_uniform_float_cmp(x, y)
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
sig [Value, Value] => Bool
machine def zr_uniform_key_less(a, b)
  if zr_fixnum_p(a) && zr_fixnum_p(b)
    return Machine.sword(a) < Machine.sword(b)
  end
  if zr_fixnum_p(a)
    return zr_uniform_float_cmp(b, a) > 0
  end
  zr_uniform_float_cmp(a, b) < 0
end

# rb_uniform_is_larger, for the check for an input that is already in
# order.
sig [Value, Value] => Bool
machine def zr_uniform_key_larger(a, b)
  if zr_fixnum_p(a) && zr_fixnum_p(b)
    return Machine.sword(a) > Machine.sword(b)
  end
  if zr_fixnum_p(a)
    return zr_uniform_float_cmp(b, a) < 0
  end
  zr_uniform_float_cmp(a, b) > 0
end

sig [Ptr, Word, Word] => Bool
machine def zr_uniform_less(base, i, j)
  zr_uniform_key_less(Pair.key(base + (i * Pair.size)), Pair.key(base + (j * Pair.size)))
end

sig [Ptr, Word, Word] => Void
machine def zr_uniform_swap(base, i, j)
  a = base + (i * Pair.size)
  b = base + (j * Pair.size)
  k = Pair.key(a)
  e = Pair.elem(a)
  Pair.set_key(a, Pair.key(b))
  Pair.set_elem(a, Pair.elem(b))
  Pair.set_key(b, k)
  Pair.set_elem(b, e)
end

# Moves the record at `i` to `pos`, and shifts the records between them
# up by one.
sig [Ptr, Word, Word] => Void
machine def zr_uniform_move(base, i, pos)
  k = Pair.key(base + (i * Pair.size))
  e = Pair.elem(base + (i * Pair.size))
  while i > pos
    Pair.set_key(base + (i * Pair.size), Pair.key(base + ((i - 1) * Pair.size)))
    Pair.set_elem(base + (i * Pair.size), Pair.elem(base + ((i - 1) * Pair.size)))
    i -= 1
  end
  Pair.set_key(base + (pos * Pair.size), k)
  Pair.set_elem(base + (pos * Pair.size), e)
end

sig [Ptr, Word, Word] => Void
machine def zr_uniform_insertion(base, a, stop)
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
sig [Ptr, Word, Word, Word] => Void
machine def zr_uniform_heap_down(base, a, offset, len)
  scratch = Machine.slot(Pair.size)
  Pair.set_key(scratch, Pair.key(base + ((a + offset) * Pair.size)))
  Pair.set_elem(scratch, Pair.elem(base + ((a + offset) * Pair.size)))
  while true
    c = (offset * 2) + 1
    break if c > len
    if c < len && zr_uniform_less(base, a + c, a + c + 1)
      c += 1
    end
    if !zr_uniform_key_less(Pair.key(scratch), Pair.key(base + ((a + c) * Pair.size)))
      break
    end
    Pair.set_key(base + ((a + offset) * Pair.size), Pair.key(base + ((a + c) * Pair.size)))
    Pair.set_elem(base + ((a + offset) * Pair.size), Pair.elem(base + ((a + c) * Pair.size)))
    offset = c
  end
  Pair.set_key(base + ((a + offset) * Pair.size), Pair.key(scratch))
  Pair.set_elem(base + ((a + offset) * Pair.size), Pair.elem(scratch))
end

sig [Ptr, Word, Word] => Void
machine def zr_uniform_heapsort(base, a, stop)
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
sig [Ptr, Word, Word, Word] => Value
machine def zr_uniform_med3(base, a, b, c)
  if zr_uniform_less(base, a, b)
    if zr_uniform_less(base, b, c)
      return Pair.key(base + (b * Pair.size))
    end
    if zr_uniform_less(base, c, a)
      return Pair.key(base + (a * Pair.size))
    end
    return Pair.key(base + (c * Pair.size))
  end
  if zr_uniform_less(base, c, b)
    return Pair.key(base + (b * Pair.size))
  end
  if zr_uniform_less(base, a, c)
    return Pair.key(base + (a * Pair.size))
  end
  Pair.key(base + (c * Pair.size))
end

sig [Ptr, Word, Word, Word] => Void
machine def zr_uniform_quicksort(base, a, stop, d)
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
    while zr_uniform_key_less(Pair.key(base + (i * Pair.size)), x)
      i += 1
    end
    while zr_uniform_key_less(x, Pair.key(base + (j * Pair.size)))
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
sig [Ptr, Word] => Void
machine def zr_uniform_sort(base, n)
  i = 1
  sorted = 1
  while i < n
    if zr_uniform_key_larger(Pair.key(base + ((i - 1) * Pair.size)), Pair.key(base + (i * Pair.size)))
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
sig [Value] => Value
machine def zr_sort_by(pairs)
  n = RArray.len(pairs) / 2
  base = RArray.ptr(pairs)
  uniform = 1
  i = 0
  while i < n
    k = Pair.key(base + (i * Pair.size))
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
    Sort.set_base(st, base)
    Sort.set_stride(st, Pair.size)
    Sort.set_blk(st, Machine.value(QNIL))
    Sort.set_failed(st, 0)
    Sort.set_plain(st, zr_sort_plain())
    zr_os_sort(st, n)
    if Sort.failed(st) != 0
      return Machine.value(QUNDEF)
    end
  end
  out = zr_ary_new(n)
  i = 0
  while i < n
    zr_ary_push(out, Pair.elem(RArray.ptr(pairs) + (i * Pair.size)))
    i += 1
  end
  out
end
