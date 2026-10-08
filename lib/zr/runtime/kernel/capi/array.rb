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
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
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
end
