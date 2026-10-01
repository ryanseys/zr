module Zr::Kern
  # Arrays: a length, a capacity and a buffer of Values outside the arena.
  # `base` is the block from malloc. `ptr` is the first element, after the
  # gap that a shift from the front leaves. `capa` counts from `ptr`.
  RArray = layout basic: RBasic, len: Word, capa: Word, ptr: Ptr, base: Ptr
  G_ARRAY = 25
  G_INDEX_ERROR = 26
  # CRuby's ARY_MAX_SIZE: the maximum number of elements in an Array,
  # LONG_MAX divided by the size of a Value.
  ARY_MAX_SIZE = 1152921504606846975

  # Returns the limit, for the core code that checks `*` and `fill`
  # against it.
  sig [] => Value
  def zr_ary_max_size
    zr_fix(ARY_MAX_SIZE)
  end

  # An embedded Array (FL_EMBED, which String also uses) keeps its
  # elements in its own cell, after the header, as many as the cell has
  # space for. A longer Array keeps them in a malloc'd block, `base`.
  # After a shift, `ptr` can point inside that block. In both cases `ptr`
  # points to the elements and `capa` counts the space from there, so a
  # reader does not need to check which case applies.
  sig [Value] => Bool
  def zr_ary_embedded_p(a)
    (RBasic.flags(a) & FL_EMBED) != 0
  end

  # The number of elements that the cell of `a` can contain: 2 in a
  # 64-byte cell, 10 in 128, 26 in 256.
  sig [Value] => Word
  def zr_ary_embed_capa(a)
    (zr_cell_bytes(a) - RArray.size) / 8
  end

  # The cell size for an Array of `capa` elements: a cell that contains
  # them all, else the smallest cell, with the elements in a malloc'd block.
  sig [Word] => Word
  def zr_ary_cell_bytes(capa)
    bytes = RArray.size + (capa * 8)
    bytes <= CELL_MAX ? bytes : RArray.size
  end

  # Makes space for `capa` elements in `a`, which has no old elements:
  # the tail of its own cell when they fit, else a malloc'd block.
  sig [Value, Word] => Void
  def zr_ary_buf_new(a, capa)
    if capa <= zr_ary_embed_capa(a)
      buf = Machine.ptr(a) + RArray.size
      capa = zr_ary_embed_capa(a)
      RBasic.set_flags(a, RBasic.flags(a) | FL_EMBED)
    else
      buf = zr_xmalloc(capa * 8)
      RBasic.set_flags(a, RBasic.flags(a) & FL_EMBED_CLEAR)
    end
    RArray.set_ptr(a, buf)
    RArray.set_base(a, buf)
    RArray.set_len(a, 0)
    RArray.set_capa(a, capa)
  end

  # Frees the buffer when it is a malloc'd block. An embedded buffer is
  # part of the cell and goes with it.
  sig [Value] => Void
  def zr_ary_buf_free(a)
    if !zr_ary_embedded_p(a)
      zr_sized_xfree(RArray.base(a), zr_ary_buf_bytes(a))
    end
  end

  # The byte size of the buffer of `a`, which starts at `base`: its
  # capacity in words, plus the front gap that shifts left before `ptr`.
  # A shift moves `ptr` up and subtracts the same count from `capa`, so
  # the sum is always the size that was allocated.
  sig [Value] => Word
  def zr_ary_buf_bytes(a)
    (RArray.capa(a) * 8) + (RArray.ptr(a) - RArray.base(a))
  end

  sig [Word] => Value
  def zr_ary_new(capa)
    a = zr_alloc(T_ARRAY, zr_global(G_ARRAY), zr_ary_cell_bytes(capa))
    zr_ary_buf_new(a, capa)
    a
  end

  # Returns the length as a fixnum, for core code that must not dispatch.
  sig [Value] => Value
  def zr_ary_len_m(a)
    zr_fix(RArray.len(a))
  end

  # Returns the element at `i`, for the same reason.
  sig [Value, Value] => Value
  def zr_ary_at_m(a, i)
    zr_ary_at(a, zr_fix2long(i))
  end

  sig [Value] => Void
  def zr_mark_ary(a)
    n = RArray.len(a)
    i = 0
    while i < n
      zr_mark(Machine.value(Machine.load64(RArray.ptr(a) + (i * 8), 0)))
      i += 1
    end
  end

  sig [Value, Word] => Value
  def zr_ary_at(a, i)
    if i < 0
      i += RArray.len(a)
    end
    if i < 0 || i >= RArray.len(a)
      return Machine.value(QNIL)
    end
    Machine.value(Machine.load64(RArray.ptr(a) + (i * 8), 0))
  end

  sig [Value, Word] => Void
  def zr_ary_reserve(a, n)
    if n > RArray.capa(a)
      len = RArray.len(a)
      gap = (RArray.ptr(a) - RArray.base(a)) / 8
      # If the front gap is at least as long as the array and closing it
      # gives enough space, move the elements back to the start of the
      # block. The copy costs no more than the shifts that made the gap,
      # so a queue stays linear.
      if gap >= len && n <= RArray.capa(a) + gap
        zr_memmove(RArray.base(a), RArray.ptr(a), len * 8)
        RArray.set_ptr(a, RArray.base(a))
        RArray.set_capa(a, RArray.capa(a) + gap)
        return
      end
      capa = RArray.capa(a) * 2
      # Doubling stops at CRuby's limit, so the byte count cannot overflow.
      if capa < n || capa > ARY_MAX_SIZE
        capa = n
      end
      p = zr_xmalloc(capa * 8)
      zr_memcpy(p, RArray.ptr(a), len * 8)
      zr_ary_buf_free(a)
      RArray.set_ptr(a, p)
      RArray.set_base(a, p)
      RArray.set_capa(a, capa)
      RBasic.set_flags(a, RBasic.flags(a) & FL_EMBED_CLEAR)
    end
  end

  sig [Value, Value] => Void
  def zr_ary_push(a, v)
    n = RArray.len(a)
    zr_ary_reserve(a, n + 1)
    Machine.store64(RArray.ptr(a) + (n * 8), 0, Machine.word(v))
    RArray.set_len(a, n + 1)
    zr_write_barrier(a, v)
  end

  sig [Value, Value] => Void
  def zr_ary_unshift(a, v)
    n = RArray.len(a)
    zr_ary_reserve(a, n + 1)
    zr_memmove(RArray.ptr(a) + 8, RArray.ptr(a), n * 8)
    Machine.store64(RArray.ptr(a), 0, Machine.word(v))
    RArray.set_len(a, n + 1)
    zr_write_barrier(a, v)
  end

  # `a[i] = v`, filling with nil past the end.
  sig [Value, Word, Value] => Value
  def zr_ary_store(a, i, v)
    n = RArray.len(a)
    if i < 0
      i += n
      if i < 0
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("index "), 6)
        zr_buf_long(b, i - n)
        zr_buf_push(b, Machine.bytes(" too small for array; minimum: "), 31)
        zr_buf_long(b, 0 - n)
        return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
      end
    elsif i >= ARY_MAX_SIZE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("index "), 6)
      zr_buf_long(b, i)
      zr_buf_push(b, Machine.bytes(" too big"), 8)
      return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
    end
    if i >= n
      zr_ary_reserve(a, i + 1)
      j = n
      while j < i
        Machine.store64(RArray.ptr(a) + (j * 8), 0, QNIL)
        j += 1
      end
      RArray.set_len(a, i + 1)
    end
    Machine.store64(RArray.ptr(a) + (i * 8), 0, Machine.word(v))
    zr_write_barrier(a, v)
    v
  end

  # An Array of the `argc` Values at `argv`.
  sig [Word, Ptr] => Value
  def zr_ary_of(argc, argv)
    a = zr_ary_new(argc)
    zr_memcpy(RArray.ptr(a), argv, argc * 8)
    RArray.set_len(a, argc)
    zr_write_barrier_all(a)
    a
  end

  # `(a..b).to_a` for two fixnums. It fills the Array here, not with one
  # yield for each element through Enumerable.
  sig [Value, Value, Value] => Value
  def zr_fixnum_range_ary(low, high, excl)
    a = zr_fix2long(low)
    b = zr_fix2long(high)
    if excl != QFALSE && excl != QNIL
      b -= 1
    end
    n = b >= a ? b - a + 1 : 0
    if n > ARY_MAX_SIZE
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("array size too big"), 18)
    end
    out = zr_ary_new(n)
    p = RArray.ptr(out)
    i = 0
    while i < n
      Machine.store64(p + (i * 8), 0, Machine.word(zr_fix(a + i)))
      i += 1
    end
    RArray.set_len(out, n)
    out
  end

  # Returns the Array for a splat: nil gives no elements, an Array gives
  # itself, an object with `to_a` gives its result, and all other values
  # give one element. A `to_a` that returns nil converts nothing, so the
  # object is the one element (rb_check_to_array).
  sig [Value] => Value
  def zr_splat_to_a(v)
    if v == QNIL
      return zr_ary_new(0)
    end
    if !zr_special_p(v) && zr_type(v) == T_ARRAY
      return v
    end
    r = zr_check_call(v, zr_sym(Machine.id(:to_a)))
    return r if r == QUNDEF
    if r == QNIL
      a = zr_ary_new(1)
      zr_ary_push(a, v)
      return a
    end
    if zr_special_p(r) || zr_type(r) != T_ARRAY
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't convert to Array (to_a gives something else)"), 50)
    end
    r
  end

  # Adds the elements of the splat `*v` to the Array `a`.
  sig [Value, Value] => Value
  def zr_ary_splat(a, v)
    v = zr_splat_to_a(v)
    return v if v == QUNDEF
    i = 0
    while i < RArray.len(v)
      zr_ary_push(a, zr_ary_at(v, i))
      i += 1
    end
    a
  end

  # `Array#initialize`: nothing, `(size, fill = nil)`, `(size) { |i| }`
  # or `(array)`.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_initialize(recv, argc, argv, cref, blk)
    if argc > 2
      return zr_wrong_arity_range(argc, 0, 2)
    end
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    RArray.set_len(recv, 0)
    if argc == 0
      return recv
    end
    first = Machine.value(Machine.load64(argv, 0))
    if argc == 1 && !zr_special_p(first) && zr_type(first) == T_ARRAY
      i = 0
      while i < RArray.len(first)
        zr_ary_push(recv, zr_ary_at(first, i))
        i += 1
      end
      return recv
    end
    n = 0
    if zr_fixnum_p(first)
      n = zr_fix2long(first)
    else
      # One argument with to_ary is copied, as rb_check_array_type finds
      # it. A size converts as NUM2LONG does.
      if argc == 1 && !zr_special_p(first) && zr_find_method(zr_class_of(first), Machine.id(:to_ary)) != 0
        given = zr_send(first, Machine.id(:to_ary), 0, 0)
        return given if given == QUNDEF
        if given != QNIL
          if zr_special_p(given) || zr_type(given) != T_ARRAY
            b = Machine.slot(Buf.size)
            zr_buf_init(b)
            zr_buf_push(b, Machine.bytes("can't convert "), 14)
            zr_buf_class_of(b, first)
            zr_buf_push(b, Machine.bytes(" to Array ("), 11)
            zr_buf_class_of(b, first)
            zr_buf_push(b, Machine.bytes("#to_ary gives "), 14)
            zr_buf_class_of(b, given)
            zr_buf_push(b, Machine.bytes(")"), 1)
            return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
          end
          i = 0
          while i < RArray.len(given)
            zr_ary_push(recv, zr_ary_at(given, i))
            i += 1
          end
          return recv
        end
      end
      size = Machine.slot(8)
      r = zr_index_operand(first, size)
      return r if r == QUNDEF
      n = Machine.load64(size, 0)
    end
    if n < 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative array size"), 19)
    end
    if n > ARY_MAX_SIZE
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("array size too big"), 18)
    end
    fill = argc == 2 ? Machine.value(Machine.load64(argv, 8)) : Machine.value(QNIL)
    if blk != QNIL && argc == 2
      zr_warn_here(Machine.bytes("block supersedes default value argument"), 39)
    end
    i = 0
    while i < n
      if blk != QNIL
        v = zr_yield1(blk, zr_fix(i))
        return v if v == QUNDEF
        zr_ary_push(recv, v)
      else
        zr_ary_push(recv, fill)
      end
      i += 1
    end
    recv
  end

  # Returns the index of `v` in `a`, compared by identity, or -1.
  sig [Value, Value] => Word
  def zr_ary_index_of(a, v)
    i = 0
    while i < RArray.len(a)
      if zr_ary_at(a, i) == v
        return i
      end
      i += 1
    end
    0 - 1
  end

  # Writes the value of a bignum to `out` when it fits a signed 64-bit
  # word, as NUM2LONG does: at most three base-2^30 limbs with the top
  # limb below 8, or exactly -2^63.
  sig [Value, Ptr] => Bool
  def zr_big_to_long(v, out)
    limbs = zr_hidden_get(v, zr_sym(Machine.id(:__limbs__)))
    neg = zr_hidden_get(v, zr_sym(Machine.id(:__neg__))) == QTRUE
    n = RArray.len(limbs)
    if n > 3
      return false
    end
    top = n == 3 ? zr_fix2long(zr_ary_at(limbs, 2)) : 0
    if top > 8
      return false
    end
    mid = n >= 2 ? zr_fix2long(zr_ary_at(limbs, 1)) : 0
    low = n >= 1 ? zr_fix2long(zr_ary_at(limbs, 0)) : 0
    if top == 8
      if !neg || mid != 0 || low != 0
        return false
      end
      Machine.store64(out, 0, 0 - 9223372036854775807 - 1)
      return true
    end
    mag = (top << 60) | (mid << 30) | low
    Machine.store64(out, 0, neg ? 0 - mag : mag)
    true
  end

  sig [Value, Ptr] => Value
  def zr_index_operand(v, out)
    unless zr_fixnum_p(v)
      if zr_float_p(v)
        d = zr_float_value(v)
        t = Machine.trunc(d)
        if zr_nan_p(d) || zr_inf_p(d) || Machine.fabs(t) >= Machine.f64(4890909195324358656)
          return zr_send(v, Machine.id(:index_range_error), 0, 0)
        end
        Machine.store64(out, 0, Machine.to_int(t))
        return Machine.value(QNIL)
      end
      if zr_big_p(v)
        if zr_big_to_long(v, out)
          return Machine.value(QNIL)
        end
        return zr_raise_msg(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'long'"), 37)
      end
      if !zr_special_p(v) && zr_find_method(zr_class_of(v), Machine.id(:to_int)) != 0
        r = zr_send(v, Machine.id(:to_int), 0, 0)
        return r if r == QUNDEF
        if zr_fixnum_p(r)
          Machine.store64(out, 0, zr_fix2long(r))
          return Machine.value(QNIL)
        end
        if zr_big_p(r)
          if zr_big_to_long(r, out)
            return Machine.value(QNIL)
          end
          return zr_raise_msg(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'long'"), 37)
        end
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("can't convert "), 14)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes(" to Integer ("), 13)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes("#to_int gives "), 14)
        zr_buf_class_of(b, r)
        zr_buf_push(b, Machine.bytes(")"), 1)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      if v == QNIL
        zr_buf_push(b, Machine.bytes("no implicit conversion from nil to integer"), 42)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      if v == QTRUE || v == QFALSE
        s = zr_inspect(v)
        return s if s == QUNDEF
        zr_buf_str(b, s)
      else
        zr_buf_class_of(b, v)
      end
      zr_buf_push(b, Machine.bytes(" into Integer"), 13)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    Machine.store64(out, 0, zr_fix2long(v))
    Machine.value(QNIL)
  end

  # `a[beg, len]`: a new Array of the elements from `beg`, or nil after
  # the end. A start at the end returns an empty Array.
  sig [Value, Word, Word] => Value
  def zr_ary_subseq(a, beg, len)
    n = RArray.len(a)
    if beg > n || beg < 0 || len < 0
      return Machine.value(QNIL)
    end
    if len > n - beg
      len = n - beg
    end
    zr_ary_of(len, RArray.ptr(a) + (beg * 8))
  end

  # Converts a Range to a start and a length for `n` elements, into `out`.
  # Returns false when the start is out of range.
  sig [Value, Word, Ptr] => Value
  def zr_range_beg_len(range, n, out)
    low = zr_ivar_get(range, Machine.id(:begin))
    high = zr_ivar_get(range, Machine.id(:end))
    slot = Machine.slot(8)
    if low == QNIL
      beg = 0
    else
      r = zr_index_operand(low, slot)
      return r if r == QUNDEF
      beg = Machine.load64(slot, 0)
    end
    if high == QNIL
      stop = n
    else
      r = zr_index_operand(high, slot)
      return r if r == QUNDEF
      stop = Machine.load64(slot, 0)
    end
    if beg < 0
      beg += n
      if beg < 0
        return Machine.value(QFALSE)
      end
    end
    if stop < 0
      stop += n
    end
    if high != QNIL && zr_ivar_get(range, Machine.id(:excl)) != QTRUE
      stop += 1
    end
    len = stop - beg
    if len < 0
      len = 0
    end
    if beg > n
      return Machine.value(QFALSE)
    end
    Machine.store64(out, 0, beg)
    Machine.store64(out, 8, len)
    Machine.value(QTRUE)
  end

  # `a[i]`, `a[beg, len]` and `a[range]`.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_aref(recv, argc, argv, cref, blk)
    first = Machine.value(Machine.load64(argv, 0))
    if argc == 1 && zr_fixnum_p(first)
      return zr_ary_at(recv, zr_fix2long(first))
    end
    out = Machine.slot(16)
    if argc == 2
      r = zr_index_operand(first, out)
      return r if r == QUNDEF
      r = zr_index_operand(Machine.value(Machine.load64(argv, 8)), out + 8)
      return r if r == QUNDEF
      beg = Machine.load64(out, 0)
      if beg < 0
        beg += RArray.len(recv)
      end
      return zr_ary_subseq(recv, beg, Machine.load64(out, 8))
    end
    if argc != 1
      return zr_wrong_arity_range(argc, 1, 2)
    end
    if !zr_special_p(first) && zr_class_of(first) == zr_global(G_RANGE)
      r = zr_range_beg_len(first, RArray.len(recv), out)
      return r if r == QUNDEF
      if r == QFALSE
        return Machine.value(QNIL)
      end
      return zr_ary_subseq(recv, Machine.load64(out, 0), Machine.load64(out, 8))
    end
    # An ArithmeticSequence slices with its stride.
    if !zr_special_p(first) && !zr_float_p(first)
      seq = zr_const_get_at(zr_core_class(Machine.id(:Enumerator)), Machine.id(:ArithmeticSequence))
      return seq if seq == QUNDEF
      if zr_is_a(first, seq)
        return zr_send(recv, Machine.id(:stride_slice), 1, argv)
      end
    end
    r = zr_index_operand(first, out)
    return r if r == QUNDEF
    zr_ary_at(recv, Machine.load64(out, 0))
  end

  # `a[x]` and `a[beg, len]` for the core: the result of Array#[], never
  # through a `[]` that a subclass defines, as the C calls rb_ary_aref1
  # and rb_ary_subseq do.
  sig [Value, Value] => Value
  def zr_ary_aref1_m(a, x)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(x))
    zr_ary_aref(a, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  sig [Value, Value, Value] => Value
  def zr_ary_aref2_m(a, beg, len)
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(beg))
    Machine.store64(slot, 8, Machine.word(len))
    zr_ary_aref(a, 2, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  # `a[i] = v` for one index.
  sig [Value, Value, Value] => Value
  def zr_ary_aset_at(recv, index, v)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    out = Machine.slot(8)
    r = zr_index_operand(index, out)
    return r if r == QUNDEF
    zr_ary_store(recv, Machine.load64(out, 0), v)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_push_m(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    i = 0
    while i < argc
      zr_ary_push(recv, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    recv
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  # The stack operations of Array: `pop`, `shift` and `unshift` (`first`
  # and `last` are Ruby, in lib/zr/runtime/core/array.rb). This code reads the
  # count of `pop(n)` and `shift(n)` (zr_ary_count), so a call with no
  # count is only a few loads. A shift does not move the elements. It
  # moves `ptr` past the first element. An unshift uses that gap again,
  # and zr_ary_reserve closes it.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_pop(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    n = RArray.len(recv)
    if argc == 0
      if n == 0
        return Machine.value(QNIL)
      end
      RArray.set_len(recv, n - 1)
      return Machine.value(Machine.load64(RArray.ptr(recv) + ((n - 1) * 8), 0))
    end
    out = Machine.slot(8)
    r = zr_ary_count(argc, argv, n, out)
    return r if r == QUNDEF
    k = Machine.load64(out, 0)
    taken = zr_ary_of(k, RArray.ptr(recv) + ((n - k) * 8))
    RArray.set_len(recv, n - k)
    taken
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_shift(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    n = RArray.len(recv)
    if argc == 0
      if n == 0
        return Machine.value(QNIL)
      end
      v = Machine.value(Machine.load64(RArray.ptr(recv), 0))
      zr_ary_drop_front(recv, 1)
      return v
    end
    out = Machine.slot(8)
    r = zr_ary_count(argc, argv, n, out)
    return r if r == QUNDEF
    k = Machine.load64(out, 0)
    taken = zr_ary_of(k, RArray.ptr(recv))
    zr_ary_drop_front(recv, k)
    taken
  end

  # `reverse!` in place, and the reversed copy that `reverse` and
  # `reverse_each` use.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_reverse_bang(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    p = RArray.ptr(recv)
    i = 0
    j = RArray.len(recv) - 1
    while i < j
      v = Machine.load64(p + (i * 8), 0)
      Machine.store64(p + (i * 8), 0, Machine.load64(p + (j * 8), 0))
      Machine.store64(p + (j * 8), 0, v)
      i += 1
      j -= 1
    end
    recv
  end

  sig [Value] => Value
  def zr_ary_reversed(a)
    n = RArray.len(a)
    out = zr_ary_new(n)
    p = RArray.ptr(a)
    q = RArray.ptr(out)
    i = 0
    while i < n
      Machine.store64(q + (i * 8), 0, Machine.load64(p + ((n - 1 - i) * 8), 0))
      i += 1
    end
    RArray.set_len(out, n)
    out
  end

  sig [Value, Word] => Void
  def zr_ary_drop_front(a, k)
    RArray.set_ptr(a, RArray.ptr(a) + (k * 8))
    RArray.set_capa(a, RArray.capa(a) - k)
    RArray.set_len(a, RArray.len(a) - k)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_unshift_m(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    if argc == 0
      return recv
    end
    n = RArray.len(recv)
    if argc <= (RArray.ptr(recv) - RArray.base(recv)) / 8
      RArray.set_ptr(recv, RArray.ptr(recv) - (argc * 8))
      RArray.set_capa(recv, RArray.capa(recv) + argc)
    else
      zr_ary_reserve(recv, n + argc)
      zr_memmove(RArray.ptr(recv) + (argc * 8), RArray.ptr(recv), n * 8)
    end
    zr_memcpy(RArray.ptr(recv), argv, argc * 8)
    zr_write_barrier_all(recv)
    RArray.set_len(recv, n + argc)
    recv
  end

  # Writes the count for `pop(n)` and `shift(n)` into `out`, limited to
  # the `n` elements that there are.
  sig [Word, Ptr, Word, Ptr] => Value
  def zr_ary_count(argc, argv, n, out)
    if argc != 1
      return zr_wrong_arity_range(argc, 0, 1)
    end
    r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
    return r if r == QUNDEF
    k = Machine.load64(out, 0)
    if k < 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative array size"), 19)
    end
    if k > n
      Machine.store64(out, 0, n)
    end
    Machine.value(QNIL)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_length(recv, argc, argv, cref, blk)
    zr_fix(RArray.len(recv))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_empty_p(recv, argc, argv, cref, blk)
    zr_bool(RArray.len(recv) == 0)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_first(recv, argc, argv, cref, blk)
    zr_ary_at(recv, 0)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_last(recv, argc, argv, cref, blk)
    zr_ary_at(recv, 0 - 1)
  end

  # `[1, 2]`: the inspect of each element can run Ruby, so the code reads
  # the buffer again by index. The text gets the encoding of the first
  # element, and each later element is appended to it, as inspect_ary
  # does. The results of rb_inspect are always compatible, so no pair
  # causes an error.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_inspect(recv, argc, argv, cref, blk)
    if RArray.len(recv) == 0
      return zr_usascii_str_new(Machine.bytes("[]"), 2)
    end
    if zr_guard_enter(recv, Machine.id(:inspect))
      return zr_usascii_str_new(Machine.bytes("[...]"), 5)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, 91)
    index = ENC_USASCII
    ascii = true
    i = 0
    while i < RArray.len(recv)
      if i > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      s = zr_inspect(zr_ary_at(recv, i))
      if s == QUNDEF
        zr_buf_free(b)
        zr_guard_leave(recv, Machine.id(:inspect))
        return s
      end
      index = i == 0 ? zr_str_encoding_index(s) : zr_enc_append_str(index, ascii, Buf.len(b), s)
      ascii = ascii && zr_str_ascii_bytes_p(s)
      zr_buf_str(b, s)
      i += 1
    end
    zr_buf_byte(b, 93)
    zr_guard_leave(recv, Machine.id(:inspect))
    zr_str_set_index(zr_buf_take(b), index)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_ary_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_ARRAY
      return Machine.value(QFALSE)
    end
    if RArray.len(recv) != RArray.len(other)
      return Machine.value(QFALSE)
    end
    if recv == other
      return Machine.value(QTRUE)
    end
    # A comparison of the same two Arrays inside their own comparison is a
    # recursion, and it returns equal (rb_exec_recursive_paired).
    if zr_guard_enter_paired(recv, other, Machine.id(:==))
      return Machine.value(QTRUE)
    end
    i = 0
    while i < RArray.len(recv)
      # The same object is equal without a call to ==, as in rb_equal.
      if zr_ary_at(recv, i) != zr_ary_at(other, i)
        slot = Machine.slot(8)
        Machine.store64(slot, 0, Machine.word(zr_ary_at(other, i)))
        r = zr_send(zr_ary_at(recv, i), Machine.id(:==), 1, slot)
        if r == QUNDEF
          zr_guard_leave(recv, Machine.id(:==))
          return r
        end
        if r == QNIL || r == QFALSE
          zr_guard_leave(recv, Machine.id(:==))
          return Machine.value(QFALSE)
        end
      end
      i += 1
    end
    zr_guard_leave(recv, Machine.id(:==))
    Machine.value(QTRUE)
  end

  # `recv[i]` as CRuby's opt_aref instruction runs it. An Array or a Hash
  # with its original `[]` is read directly, with no frame for a backtrace.
  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_aref(recv, mid, argc, argv, mode)
    if !zr_special_p(recv)
      k = RBasic.klass(recv)
      if k == zr_global(G_ARRAY) && (Machine.gates & GATE_AREF) == 0
        return zr_ary_aref(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
      if argc == 1 && k == zr_global(G_HASH) && (Machine.gates & GATE_HASH_AREF) == 0
        return zr_hash_aref(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  # `recv.push(v)`, `recv.pop`, `recv.shift` and `recv.empty?` on an Array
  # with its original methods. These run the builtin body directly, with
  # no frame, as `<<` does. The builtin path (zr_builtin_fn) was a third
  # of the time of `bm_so_lists`, which uses these four on two lists.
  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_push(recv, mid, argc, argv, mode)
    if argc == 1 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.gates & GATE_PUSH) == 0
      return zr_ary_push_m(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_pop(recv, mid, argc, argv, mode)
    if argc == 0 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.gates & GATE_POP) == 0
      return zr_ary_pop(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_shift(recv, mid, argc, argv, mode)
    if argc == 0 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.gates & GATE_SHIFT) == 0
      return zr_ary_shift(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_empty_p(recv, mid, argc, argv, mode)
    if argc == 0 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.gates & GATE_EMPTY_P) == 0
      return zr_bool(RArray.len(recv) == 0)
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  # `recv[k] = v`, the same way: an Array for an Integer index, a Hash for
  # all keys.
  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_aset(recv, mid, argc, argv, mode)
    if argc == 2 && !zr_special_p(recv)
      k = RBasic.klass(recv)
      if k == zr_global(G_ARRAY) && (Machine.gates & GATE_ASET) == 0 && zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
        return zr_ary_aset_at(recv, Machine.value(Machine.load64(argv, 0)), Machine.value(Machine.load64(argv, 8)))
      end
      if k == zr_global(G_HASH) && (Machine.gates & GATE_HASH_ASET) == 0
        return zr_hash_aset(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  # Returns the Array for a multiple assignment: the value if it is an
  # Array, its `to_ary` if it has one, else an Array of the value.
  sig [Value] => Value
  def zr_masgn_ary(v)
    if !zr_special_p(v) && zr_type(v) == T_ARRAY
      return v
    end
    responds = zr_special_p(v) ? Machine.value(QFALSE) : zr_check_funcall(v, Machine.id(:to_ary))
    return responds if responds == QUNDEF
    if responds == QTRUE
      a = zr_send(v, Machine.id(:to_ary), 0, 0)
      return a if a == QUNDEF
      if !zr_special_p(a) && zr_type(a) == T_ARRAY
        return a
      end
      if a != QNIL
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't convert to Array (to_ary gives something else)"), 52)
      end
    end
    a = zr_ary_new(1)
    zr_ary_push(a, v)
    a
  end

  # `a, *rest, b = ary`: the elements between the first `nlefts` and the
  # last `nrights`, or an empty Array.
  sig [Value, Word, Word] => Value
  def zr_masgn_rest(ary, nlefts, nrights)
    from = nlefts
    to = RArray.len(ary) - nrights
    if to < from
      to = from
    end
    out = zr_ary_new(to - from)
    i = from
    while i < to
      zr_ary_push(out, zr_ary_at(ary, i))
      i += 1
    end
    out
  end

  # The value of the `i`th of the `nrights` targets after a rest: from
  # the end when the Array is long enough, else immediately after the
  # `nlefts`.
  sig [Value, Word, Word, Word] => Value
  def zr_masgn_right(ary, nlefts, nrights, i)
    start = RArray.len(ary) - nrights
    if start < nlefts
      start = nlefts
    end
    zr_ary_at(ary, start + i)
  end

  # `a[beg, len] = vals`, the one edit that all mutations use. It removes
  # the `len` elements from `beg` and puts the elements of `vals` in their
  # place. A start after the end first fills with nil.
  sig [Value, Value, Value, Value] => Value
  def zr_ary_splice(a, beg_v, len_v, vals)
    if zr_modify_frozen_p(a)
      return zr_frozen_error(a)
    end
    beg = zr_fix2long(beg_v)
    len = zr_fix2long(len_v)
    n = RArray.len(a)
    if len < 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("negative length ("), 17)
      zr_buf_long(b, len)
      zr_buf_byte(b, 41)
      return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
    end
    if beg < 0
      beg += n
      if beg < 0
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("index "), 6)
        zr_buf_long(b, beg - n)
        zr_buf_push(b, Machine.bytes(" too small for array; minimum: "), 31)
        zr_buf_long(b, 0 - n)
        return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
      end
    end
    # The length of `vals` before the fill, which grows `vals` too when it
    # is `a` itself.
    m = RArray.len(vals)
    if beg > n
      zr_ary_store(a, beg - 1, Machine.value(QNIL))
      n = beg
    end
    if beg + len > n
      len = n - beg
    end
    # At the front, the elements do not move and `ptr` moves: a shift
    # leaves a gap, and an unshift that fits uses the gap again.
    if beg == 0 && m <= len
      RArray.set_ptr(a, RArray.ptr(a) + ((len - m) * 8))
      RArray.set_capa(a, RArray.capa(a) - (len - m))
      zr_memcpy(RArray.ptr(a), RArray.ptr(vals), m * 8)
      RArray.set_len(a, n - len + m)
      zr_write_barrier_all(a)
      return a
    end
    if beg == 0 && (m - len) <= (RArray.ptr(a) - RArray.base(a)) / 8
      RArray.set_ptr(a, RArray.ptr(a) - ((m - len) * 8))
      RArray.set_capa(a, RArray.capa(a) + (m - len))
      zr_memcpy(RArray.ptr(a), RArray.ptr(vals), m * 8)
      RArray.set_len(a, n - len + m)
      zr_write_barrier_all(a)
      return a
    end
    tail = n - beg - len
    zr_ary_reserve(a, n - len + m)
    p = RArray.ptr(a)
    if m != len
      zr_memmove(p + ((beg + m) * 8), p + ((beg + len) * 8), tail * 8)
    end
    zr_memcpy(p + (beg * 8), RArray.ptr(vals), m * 8)
    RArray.set_len(a, n - len + m)
    zr_write_barrier_all(a)
    a
  end

  # Moves bytes between overlapping ranges, in the order that keeps them
  # correct.
  sig [Ptr, Ptr, Word] => Void
  def zr_memmove(to, from, n)
    Libc.memmove(to, from, n)
  end

  sig [Value, Value] => Value
  def zr_ary_clear(a, unused)
    if zr_modify_frozen_p(a)
      return zr_frozen_error(a)
    end
    RArray.set_len(a, 0)
    a
  end

  # Converts to an Integer index for the core, as NUM2LONG does: the
  # Integer, or its `to_int`, in the range of a signed 64-bit word. A
  # value past the fixnum range comes back as a bignum. Other values get
  # CRuby's TypeError or RangeError.
  sig [Value] => Value
  def zr_index_operand_m(v)
    if zr_fixnum_p(v)
      return v
    end
    out = Machine.slot(8)
    r = zr_index_operand(v, out)
    return r if r == QUNDEF
    zr_int_from_word(Machine.load64(out, 0))
  end
end
