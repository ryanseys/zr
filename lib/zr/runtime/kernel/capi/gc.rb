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

  # rb_obj_memsize_of: the bytes that `obj` uses, as
  # ObjectSpace.memsize_of gives them.
  #: (value) -> word
  def rb_obj_memsize_of(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_fix2long(zr_objspace_memsize(obj))
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

  # ruby_strdup: a copy of a C string in ruby's malloc.
  #: (ptr) -> ptr
  def ruby_strdup(text)
    Machine.gates_enter
    zr_c_entered()
    n = zr_cstr_len(text) + 1
    copy = zr_xmalloc(n)
    zr_memcpy(copy, text, n)
    copy
  end

  # rb_alloc_tmp_buffer_with_count: `size` bytes that C uses for a while
  # (ALLOCV), kept by a binary String that `*store` holds, so the
  # collector frees them once nothing holds the String.
  #: (ptr, word, word) -> ptr
  def rb_alloc_tmp_buffer_with_count(store, size, count)
    Machine.gates_enter
    zr_c_entered()
    buffer = zr_capi_str(Machine.ptr(0), size, ENC_BINARY)
    Machine.store64(store, 0, Machine.word(buffer))
    RString[buffer].ptr
  end

  # rb_free_tmp_buffer: lets the collector free the buffer.
  #: (ptr) -> void
  def rb_free_tmp_buffer(store)
    Machine.gates_enter
    zr_c_entered()
    Machine.store64(store, 0, 0)
  end

  # rb_gc_enable and rb_gc_disable: GC.enable and GC.disable, each true
  # when collection was off before.
  #: () -> value
  def rb_gc_enable
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:GC)), Machine.id(:enable), 0, Machine.ptr(0)))
  end

  #: () -> value
  def rb_gc_disable
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:GC)), Machine.id(:disable), 0, Machine.ptr(0)))
  end

  # rb_during_gc: whether a collection runs, as 1 or 0: only a mark or a
  # free function that it calls sees 1.
  #: () -> i32
  def rb_during_gc
    Machine.gates_enter
    zr_c_entered()
    Heap[zr_heap()].collecting != 0 ? Machine.i32(1) : Machine.i32(0)
  end

  # rb_alloc_tmp_buffer: rb_alloc_tmp_buffer_with_count of `len` bytes.
  #: (ptr, word) -> ptr
  def rb_alloc_tmp_buffer(store, len)
    Machine.gates_enter
    zr_c_entered()
    buffer = zr_capi_str(Machine.ptr(0), len, ENC_BINARY)
    Machine.store64(store, 0, Machine.word(buffer))
    RString[buffer].ptr
  end

  # rb_gc_stat: GC.stat's value of the Symbol `key`; for a Hash, GC.stat
  # fills it, and the answer is 0.
  #: (value) -> word
  def rb_gc_stat(key)
    Machine.gates_enter
    zr_c_entered()
    stat = zr_capi_call1(zr_core_class(Machine.id(:GC)), Machine.id(:stat), key)
    zr_symbol_p(key) ? zr_capi_ulong_of(stat, false) : 0
  end

  # rb_gc_latest_gc_info: GC.latest_gc_info, or its value of the Symbol
  # `key`.
  #: (value) -> value
  def rb_gc_latest_gc_info(key)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_core_class(Machine.id(:GC)), Machine.id(:latest_gc_info), key)
  end

  # rb_objspace_each_objects: calls `fn(start, end, stride, data)` over
  # the heap until it answers other than 0. CRuby gives each page, free
  # slots and internal objects too; zr gives each object that the
  # program can see as a range of its own cell, so the C loop over
  # `start...end` by `stride` meets only live objects. They are copied
  # into an Array first, as ObjectSpace.each_object does, so what `fn`
  # allocates is not in the walk.
  #: (ptr, word) -> void
  def rb_objspace_each_objects(fn, data)
    Machine.gates_enter
    zr_c_entered()
    objects = zr_objspace_objects(Machine.value(QNIL))
    argv = Machine.slot(32)
    Machine.store64(argv, 24, data)
    i = 0
    while i < RArray[objects].len
      v = zr_ary_at(objects, i)
      bytes = zr_cell_bytes(v)
      Machine.store64(argv, 0, Machine.word(v))
      Machine.store64(argv, 8, Machine.word(v) + bytes)
      Machine.store64(argv, 16, bytes)
      r = zr_call_c(fn, argv, 4)
      if r == QUNDEF
        zr_c_unwind()
      end
      if Machine.i32(r) != Machine.i32(0)
        return
      end
      i += 1
    end
  end

  # rb_gc_adjust_memory_usage: C's own memory grew by `diff` bytes (or
  # shrank, below 0), which counts toward the next collection as the
  # payload of objects does.
  #: (word) -> void
  def rb_gc_adjust_memory_usage(diff)
    Machine.gates_enter
    zr_c_entered()
    h = zr_heap()
    if diff < 0 && Heap[h].malloced < 0 - diff
      Heap[h].malloced = 0
    else
      Heap[h].malloced = Heap[h].malloced + diff
    end
    zr_heap_slow_update()
  end
end
