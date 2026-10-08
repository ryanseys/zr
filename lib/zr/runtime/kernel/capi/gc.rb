module Zr::Kern
  # The C API's view of the collector: marks from a T_DATA's mark
  # function, the write barrier, registered roots, and ruby's malloc.

  # rb_gc_mark: marks `v`; a mark function calls it for each Value its
  # struct holds. rb_gc_mark_movable is the same, as nothing moves.
  #: (value) -> void
  def rb_gc_mark(v)
    Machine.gates_enter
    zr_c_entered()
    zr_mark(v)
  end

  #: (value) -> void
  def rb_gc_mark_movable(v)
    Machine.gates_enter
    zr_c_entered()
    zr_mark(v)
  end

  # rb_gc_mark_maybe: marks `v` if it is a live object, whatever word it is.
  #: (word) -> void
  def rb_gc_mark_maybe(v)
    Machine.gates_enter
    zr_c_entered()
    zr_mark_maybe(v)
  end

  # rb_gc_mark_locations: rb_gc_mark_maybe for each word in [from, to).
  #: (ptr, ptr) -> void
  def rb_gc_mark_locations(from, to)
    Machine.gates_enter
    zr_c_entered()
    zr_mark_range(from, to)
  end

  # rb_gc_location: where `v` moved to. Nothing moves, so `v`.
  #: (value) -> value
  def rb_gc_location(v)
    Machine.gates_enter
    zr_c_entered()
    v
  end

  # rb_gc_writebarrier: C stored `young` into `owner` (RB_OBJ_WRITE).
  #: (value, value) -> void
  def rb_gc_writebarrier(owner, young)
    Machine.gates_enter
    zr_c_entered()
    if !zr_special_p(young)
      zr_write_barrier(owner, young)
    end
  end

  # rb_gc_writebarrier_remember: C changed `owner`'s Values in bulk.
  #: (value) -> void
  def rb_gc_writebarrier_remember(owner)
    Machine.gates_enter
    zr_c_entered()
    zr_write_barrier_all(owner)
  end

  # rb_gc_writebarrier_unprotect: C will store into `v` without the
  # barrier from now on (RARRAY_PTR, for one).
  #: (value) -> void
  def rb_gc_writebarrier_unprotect(v)
    Machine.gates_enter
    zr_c_entered()
    if !zr_special_p(v)
      zr_write_barrier_all(v)
      zr_unprotected_add(v)
    end
  end

  # rb_gc_register_address: the VALUE at `at`, a C global, is a root, as
  # rb_global_variable makes it.
  #: (ptr) -> void
  def rb_gc_register_address(at)
    Machine.gates_enter
    zr_c_entered()
    zr_weak_list_push(zr_c_root_addresses(), Machine.value(Machine.word(at)))
  end

  #: (ptr) -> void
  def rb_global_variable(at)
    Machine.gates_enter
    zr_c_entered()
    zr_weak_list_push(zr_c_root_addresses(), Machine.value(Machine.word(at)))
  end

  #: (ptr) -> void
  def rb_gc_unregister_address(at)
    Machine.gates_enter
    zr_c_entered()
    zr_c_root_address_drop(at)
  end

  # rb_gc_register_mark_object: `v` lives as long as the program.
  #: (value) -> void
  def rb_gc_register_mark_object(v)
    Machine.gates_enter
    zr_c_entered()
    zr_weak_list_push(zr_c_root_objects(), v)
  end

  # rb_gc_start, rb_gc: a full collection, as GC.start runs it.
  #: () -> void
  def rb_gc_start
    Machine.gates_enter
    zr_c_entered()
    zr_collect_kind(SIZE_CLASSES, true)
  end

  #: () -> void
  def rb_gc
    Machine.gates_enter
    zr_c_entered()
    zr_collect_kind(SIZE_CLASSES, true)
  end

  # ruby_xmalloc and its kin: the malloc that counts toward the
  # collector's payload limit, and stops with NoMemoryError's fatal
  # message when the system has no memory.
  #: (word) -> ptr
  def ruby_xmalloc(size)
    Machine.gates_enter
    zr_c_entered()
    zr_xmalloc(size == 0 ? 1 : size)
  end

  #: (word, word) -> ptr
  def ruby_xmalloc2(n, size)
    Machine.gates_enter
    zr_c_entered()
    zr_xmalloc(zr_capi_size(n, size, Machine.bytes("malloc"), 6))
  end

  #: (word, word) -> ptr
  def ruby_xcalloc(n, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_zalloc(zr_capi_size(n, size, Machine.bytes("calloc"), 6))
  end

  #: (ptr, word) -> ptr
  def ruby_xrealloc(p, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_realloc(p, size == 0 ? 1 : size)
  end

  #: (ptr, word, word) -> ptr
  def ruby_xrealloc2(p, n, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_realloc(p, zr_capi_size(n, size, Machine.bytes("realloc"), 7))
  end

  #: (ptr) -> void
  def ruby_xfree(p)
    Machine.gates_enter
    zr_c_entered()
    zr_xfree(p)
  end

  # ruby_malloc_size_overflow: the ArgumentError of a count times a size
  # that overflows.
  #: (word, word) -> void
  def ruby_malloc_size_overflow(count, size)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("malloc: possible integer overflow ("), 35)
    zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(count))))
    zr_buf_byte(b, 42)
    zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(size))))
    zr_buf_byte(b, 41)
    zr_c_result(zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b))
  end

  # `n * size`, or CRuby's ArgumentError when the product overflows, as
  # ruby_xmalloc2 raises it.
  #: (word, word, ptr, word) -> word
  def zr_capi_size(n, size, what, len)
    if size != 0 && Machine.ptr(n) > Machine.ptr(0 - 1) / Machine.ptr(size)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("integer overflow: "), 18)
      zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(n))))
      zr_buf_push(b, Machine.bytes(" * "), 3)
      zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(size))))
      zr_buf_push(b, Machine.bytes(" > "), 3)
      zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(0 - 1))))
      zr_c_result(zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b))
    end
    n * size == 0 ? 1 : n * size
  end

  # realloc that keeps the payload count, or stops when out of memory.
  #: (ptr, word) -> ptr
  def zr_capi_realloc(p, size)
    if p == 0
      return zr_xmalloc(size)
    end
    before = zr_os_malloc_size(p)
    q = Libc.realloc(p, size)
    if q == 0
      zr_memory_exhausted()
    end
    h = zr_heap()
    left = before > Heap[h].malloced ? 0 : Heap[h].malloced - before
    Heap[h].malloced = left + size
    if Heap[h].malloced > Heap[h].malloc_limit
      Heap[h].slow = 1
    end
    q
  end
end
