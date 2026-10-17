module Zr::Kern
  # The C API's Arrays. An Array has CRuby's heap layout (RArray: `len`,
  # `capa`, `ptr`, and RARRAY_EMBED_FLAG clear), so RARRAY_LEN and
  # RARRAY_AREF read it inline.

  # rb_ary_new: a new empty Array.
  #: () -> value
  def rb_ary_new
    Machine.gates_enter
    zr_c_entered()
    zr_ary_new(0)
  end

  # rb_ary_new_capa: a new empty Array with room for `capa` elements.
  #: (word) -> value
  def rb_ary_new_capa(capa)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ary_check_capa(capa)
    zr_ary_new(capa)
  end

  # rb_ary_new_from_values: a new Array of the `n` Values at `values`.
  #: (word, ptr) -> value
  def rb_ary_new_from_values(n, values)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ary_check_capa(n)
    ary = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(ary, Machine.value(Machine.load64(values + (i * 8), 0)))
      i += 1
    end
    ary
  end

  # rb_ary_new_from_args: a new Array of the `n` Values that follow.
  #: (word) -> value
  def rb_ary_new_from_args(n)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.va_list(VA_LIST_KIND)
    zr_capi_ary_check_capa(n)
    ary = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(ary, Machine.value(zr_va_next_word(list)))
      i += 1
    end
    ary
  end

  # rb_ary_push: appends `v`, and returns the Array.
  #: (value, value) -> value
  def rb_ary_push(ary, v)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    zr_ary_push(ary, v)
    ary
  end

  # rb_ary_entry: the element at `offset`, from the end when negative, or
  # nil.
  #: (value, word) -> value
  def rb_ary_entry(ary, offset)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(ary, offset)
  end

  # rb_ary_store: `ary[offset] = v`.
  #: (value, word, value) -> void
  def rb_ary_store(ary, offset, v)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    zr_c_result(zr_ary_store(ary, offset, v))
  end

  # rb_ary_replace: `copy.replace(orig)`.
  #: (value, value) -> value
  def rb_ary_replace(copy, orig)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(copy, Machine.id(:replace), orig)
  end

  # rb_ary_clear: empties the Array, and returns it.
  #: (value) -> value
  def rb_ary_clear(ary)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    RArray[ary].len = 0
    ary
  end

  # CRuby's `negative array size (or size too big)` and `array size too
  # big` (ArgumentError).
  #: (word) -> void
  def zr_capi_ary_check_capa(n)
    if n < 0
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative array size (or size too big)"), 37)
    end
    if n > ARY_MAX_SIZE
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("array size too big"), 18)
    end
  end

  # rb_ary_unshift: puts `v` first, and returns the Array.
  #: (value, value) -> value
  def rb_ary_unshift(ary, v)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    zr_ary_unshift(ary, v)
    ary
  end

  # rb_ary_pop: removes the last element and returns it, or nil.
  #: (value) -> value
  def rb_ary_pop(ary)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    zr_ary_pop(ary, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  # rb_ary_includes: whether `ary` has an element `== item`.
  #: (value, value) -> value
  def rb_ary_includes(ary, item)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(ary, Machine.id(:include?), item)
  end

  # rb_ary_resize: cuts `ary` to `len` elements or fills it with nil up
  # to them, and returns it.
  #: (value, word) -> value
  def rb_ary_resize(ary, len)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    if len < RArray[ary].len
      RArray[ary].len = len
    end
    while RArray[ary].len < len
      zr_ary_push(ary, Machine.value(QNIL))
    end
    ary
  end

  # rb_assoc_new: the pair `[key, value]`.
  #: (value, value) -> value
  def rb_assoc_new(key, v)
    Machine.gates_enter
    zr_c_entered()
    pair = zr_ary_new(2)
    zr_ary_push(pair, key)
    zr_ary_push(pair, v)
    pair
  end

  # rb_ary_join: `ary.join(sep)`.
  #: (value, value) -> value
  def rb_ary_join(ary, sep)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(ary, Machine.id(:join), sep)
  end

  # rb_ary_shift: removes the first element and returns it, or nil.
  #: (value) -> value
  def rb_ary_shift(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:shift), 0, Machine.ptr(0)))
  end

  # rb_ary_to_ary: `obj` as an Array: itself, what its `to_ary` gives, or
  # `[obj]`.
  #: (value) -> value
  def rb_ary_to_ary(obj)
    Machine.gates_enter
    zr_c_entered()
    ary = zr_capi_check_convert(obj, T_ARRAY, Machine.bytes("Array"), 5, Machine.id(:to_ary))
    if ary != QNIL
      return ary
    end
    one = zr_ary_new(1)
    zr_ary_push(one, obj)
    one
  end

  # rb_ary_subseq: `ary[beg, len]`.
  #: (value, word, word) -> value
  def rb_ary_subseq(ary, beg, len)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_fix(beg)))
    Machine.store64(args, 8, Machine.word(zr_fix(len)))
    zr_c_result(zr_send(ary, Machine.id(:[]), 2, args))
  end

  # rb_ary_aref: `ary[*args]`.
  #: (i32, ptr, value) -> value
  def rb_ary_aref(argc, argv, ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:[]), Machine.sword(argc), argv))
  end

  # rb_ary_dup: a new Array of the same elements.
  #: (value) -> value
  def rb_ary_dup(ary)
    Machine.gates_enter
    zr_c_entered()
    copy = zr_ary_new(RArray[ary].len)
    i = 0
    while i < RArray[ary].len
      zr_ary_push(copy, zr_ary_at(ary, i))
      i += 1
    end
    copy
  end

  # rb_ary_concat, rb_ary_delete_at, rb_ary_sort_bang and rb_ary_to_s:
  # Array#concat, #delete_at, #sort! and #to_s.
  #: (value, value) -> value
  def rb_ary_concat(ary, other)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(ary, Machine.id(:concat), other)
  end

  # rb_ary_delete: `ary.delete(item)`, with no block.
  #: (value, value) -> value
  def rb_ary_delete(ary, item)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(ary, Machine.id(:delete), item)
  end

  #: (value, word) -> value
  def rb_ary_delete_at(ary, pos)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(ary, Machine.id(:delete_at), zr_int_from_word(pos))
  end

  #: (value) -> value
  def rb_ary_sort_bang(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:sort!), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_ary_to_s(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:to_s), 0, Machine.ptr(0)))
  end

  # rb_ary_hidden_new and rb_ary_tmp_new: an Array that C uses for itself
  # with room for `capa` elements, which ObjectSpace does not give out.
  #: (word) -> value
  def rb_ary_hidden_new(capa)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ary_hidden(capa)
  end

  #: (word) -> value
  def rb_ary_tmp_new(capa)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ary_hidden(capa)
  end

  #: (word) -> value
  def zr_capi_ary_hidden(capa)
    ary = zr_ary_new(capa)
    RBasic[ary].flags = RBasic[ary].flags | FL_CONCEALED
    ary
  end

  # rb_ary_ptr_use_start and rb_ary_ptr_use_end (RARRAY_PTR_USE): the
  # elements, which C may store to with no write barrier, so the Array
  # leaves the barrier's protection, as RARRAY_PTR makes it.
  #: (value) -> ptr
  def rb_ary_ptr_use_start(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_write_barrier_all(ary)
    zr_unprotected_add(ary)
    RArray[ary].ptr
  end

  #: (value) -> void
  def rb_ary_ptr_use_end(ary)
    Machine.gates_enter
    zr_c_entered()
  end

  # rb_mem_clear: `n` nils at `mem`.
  #: (ptr, word) -> void
  def rb_mem_clear(mem, n)
    Machine.gates_enter
    zr_c_entered()
    i = 0
    while i < n
      Machine.store64(mem + (i * 8), 0, QNIL)
      i += 1
    end
  end

  # rb_ary_cat: appends the `len` Values at `argv`.
  #: (value, ptr, word) -> value
  def rb_ary_cat(ary, argv, len)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(ary)
      zr_c_result(zr_frozen_error(ary))
    end
    i = 0
    while i < len
      zr_ary_push(ary, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    ary
  end

  # rb_ary_reverse and rb_ary_freeze: Array#reverse! and #freeze.
  #: (value) -> value
  def rb_ary_reverse(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:reverse!), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_ary_freeze(ary)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(ary, Machine.id(:freeze), 0, Machine.ptr(0)))
  end

  # rb_enum_values_pack: the values that a yield gave, as one: nil for
  # none, the value for one, else an Array of them.
  #: (i32, ptr) -> value
  def rb_enum_values_pack(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(argc)
    if n == 0
      return Machine.value(QNIL)
    end
    n == 1 ? Machine.value(Machine.load64(argv, 0)) : zr_ary_of(n, argv)
  end
end
