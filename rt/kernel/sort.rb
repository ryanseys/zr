# Sorting. ruby's `Array#sort` is the C library's `qsort_r`, so a tie's
# order is that routine's, and `zr_os_sort` names the OS's. On macOS it
# is the Bentley-McIlroy algorithm here, over rows of `stride` bytes whose
# first word is the Value compared, index for pointer; musl's smoothsort
# is rt/kernel/os/linux/smoothsort.rb.
#
# The comparator runs Ruby. Once a comparison raises, every later one
# answers 0 without running Ruby, the sort finishes on the copy it was
# given, and the signal leaves after it.
Machine.struct :Sort, base: Ptr, stride: Word, blk: Value, failed: Word

# `x <=> y` as -1, 0 or 1, the way CRuby reads a comparison's answer:
# an Integer's sign, else `> 0` then `< 0`; nil fails.
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

# `comparison of X with Y failed`: Y is inspected when it is a special
# constant, else named by its class.
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

# The elements at `i` and `j` compared through the block, or `<=>`.
sig [Ptr, Word, Word] => Word
machine def zr_sort_cmp(st, i, j)
  if Sort.failed(st) != 0
    return 0
  end
  x = zr_sort_at(st, i)
  y = zr_sort_at(st, j)
  if Sort.blk(st) == QNIL
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

# `n` elements from index `a`, in the order CRuby's mmkubo sort does its
# work: each split sorts its left part, then its right part. A right
# part waits on a stack of its own rather than the machine's, so however
# badly the pivots split, the sort cannot run out of stack.
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

# One split of `n` elements from index `a`: true with the sizes of the
# left part (from `a`) and the right part (ending at `a + n`) in `parts`,
# or false when the range is sorted already.
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

# `ary` sorted in place; it is a copy the caller made, so a comparison
# that raises leaves the original as it was, and the copy keeps every
# element reachable while the block runs.
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

# The sorted copy's elements are copied back over the receiver's, and
# its length too: what a block did to the receiver while it sorted is
# lost, as in CRuby.
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

# `sort_by`'s rows: a key and its element, in an Array of pairs. When
# every key is a fixnum or a Float, CRuby sorts with its own introsort
# instead of `qsort_r`, and a tie's order is that routine's.
Machine.struct :Pair, key: Value, elem: Value

# The first two keys a uniform sort could not compare (a NaN), held
# until the sort has put every row back: the error's text allocates,
# and a row being moved lives only in a scratch slot the collector does
# not see. Until then every comparison answers that neither is less.
sig [] => Ptr
machine def zr_uniform_failed
  Machine.static(:uniform_failed, 24)
end

# `x <=> y` for a Float `x` and a fixnum or Float `y`, as rb_float_cmp
# reads it; a NaN is recorded as the failure and answers 0.
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

# rb_uniform_is_less: two fixnums by their words, else through the
# Float side, which comes first in the comparison, as CRuby puts it.
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

# rb_uniform_is_larger, which the check for an ordered input asks.
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

# The row at `i` moved to `pos`, the rows between shifted up by one.
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

# The heap under `a`: `offset` sifted down, the live region ending at
# `a + len`.
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

# The pivot: the median of three rows, as a key.
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

# The rows already in order are left alone; else an introsort whose
# depth budget is twice the bit length of `n`.
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

# `pairs` holds a key and its element in turn. The elements in key
# order, or `undef` when a comparison raised.
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
