module Zr::Kern
  # The C API of IO::Buffer: buffers over C's memory, the bytes of a
  # buffer, which C reads or writes in place, as io-event's selectors do,
  # and the buffer's methods. Each call goes through IO::Buffer.c_call,
  # which checks the buffer as ruby's C does.

  # rb_io_buffer_p: whether `v` is a buffer, a Storage or a Slice.
  #: (value) -> i32
  def rb_io_buffer_p(v)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_call1(zr_capi_buffer_class(), Machine.id(:===), v) == QTRUE ? 1 : 0)
  end

  #: (value) -> i32
  def rb_io_buffer_readonly_p(buffer)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_buffer_send(buffer, Machine.id(:readonly?), 0, QNIL, QNIL, QNIL, QNIL) == QTRUE ? 1 : 0)
  end

  # rb_io_buffer_new: a Storage over the `size` bytes of C's memory at
  # `base`, or new memory that `flags` choose for a NULL `base`.
  #: (ptr, word, i32) -> value
  def rb_io_buffer_new(base, size, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_new(base, size, flags)
  end

  # rb_io_buffer_new_locked: the same, with one lock held, for
  # rb_io_buffer_free_locked.
  #: (ptr, word, i32) -> value
  def rb_io_buffer_new_locked(base, size, flags)
    Machine.gates_enter
    zr_c_entered()
    buffer = zr_capi_buffer_new(base, size, flags)
    zr_capi_buffer_send(buffer, Machine.id(:c_lock), 0, QNIL, QNIL, QNIL, QNIL)
  end

  #: (ptr, word, i32) -> value
  def zr_capi_buffer_new(base, size, flags)
    storage = zr_capi_call1(zr_capi_buffer_class(), Machine.id(:const_get), zr_sym(Machine.id(:Storage)))
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.word(zr_capi_unsigned(Machine.word(base))))
    Machine.store64(args, 8, Machine.word(zr_capi_unsigned(size)))
    Machine.store64(args, 16, Machine.word(zr_fix(Machine.sword(flags))))
    zr_c_result(zr_send(storage, Machine.id(:c_new), 3, args))
  end

  # rb_io_buffer_map: `size` bytes of the file of `io` from `offset`.
  #: (value, word, word, i32) -> value
  def rb_io_buffer_map(io, size, offset, flags)
    Machine.gates_enter
    zr_c_entered()
    storage = zr_capi_call1(zr_capi_buffer_class(), Machine.id(:const_get), zr_sym(Machine.id(:Storage)))
    args = Machine.slot(32)
    Machine.store64(args, 0, Machine.word(io))
    Machine.store64(args, 8, Machine.word(zr_capi_unsigned(size)))
    Machine.store64(args, 16, Machine.word(zr_c_result(zr_int_from_word(offset))))
    Machine.store64(args, 24, Machine.word(zr_fix(Machine.sword(flags))))
    zr_c_result(zr_send(storage, Machine.id(:map), 4, args))
  end

  # rb_io_buffer_lock, _unlock and _try_unlock: the lock count of the
  # Storage under the buffer.
  #: (value) -> value
  def rb_io_buffer_lock(buffer)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:c_lock), 0, QNIL, QNIL, QNIL, QNIL)
  end

  #: (value) -> value
  def rb_io_buffer_unlock(buffer)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:c_unlock), 0, QNIL, QNIL, QNIL, QNIL)
  end

  #: (value) -> i32
  def rb_io_buffer_try_unlock(buffer)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_buffer_send(buffer, Machine.id(:c_try_unlock), 0, QNIL, QNIL, QNIL, QNIL) == QTRUE ? 1 : 0)
  end

  #: (value) -> value
  def rb_io_buffer_free(buffer)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:c_free), 0, QNIL, QNIL, QNIL, QNIL)
  end

  #: (value) -> value
  def rb_io_buffer_free_locked(buffer)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:free_locked), 0, QNIL, QNIL, QNIL, QNIL)
  end

  # rb_io_buffer_get_bytes: the address and the size of the bytes, and
  # the flags, READONLY when the view or a source under it is; 0 for a
  # buffer that is no longer valid.
  #: (value, ptr, ptr) -> i32
  def rb_io_buffer_get_bytes(buffer, base, size)
    Machine.gates_enter
    zr_c_entered()
    window = zr_capi_buffer_send(buffer, Machine.id(:c_bytes), 0, QNIL, QNIL, QNIL, QNIL)
    if window == QNIL
      return Machine.i32(0)
    end
    zr_capi_buffer_window(window, base, size, false)
    Machine.i32(zr_fix2long(zr_ary_at(window, 3)))
  end

  # rb_io_buffer_get_bytes_for_reading and _for_writing: the address of
  # the buffer's bytes to `*base` and their count to `*size` (NULL and 0
  # for a buffer with none). C may not write a read-only buffer.
  #: (value, ptr, ptr) -> void
  def rb_io_buffer_get_bytes_for_reading(buffer, base, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_bytes(buffer, base, size, false)
  end

  #: (value, ptr, ptr) -> void
  def rb_io_buffer_get_bytes_for_writing(buffer, base, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_bytes(buffer, base, size, true)
  end

  #: (value, ptr, ptr, bool) -> void
  def zr_capi_buffer_bytes(buffer, base, size, writing)
    window = zr_capi_buffer_send(buffer, Machine.id(:c_window), 1, zr_bool(writing), QNIL, QNIL, QNIL)
    zr_capi_buffer_window(window, base, size, writing)
  end

  # Stores the address and the size of a window (`c_window`, `c_bytes`):
  # the String or the address that holds the bytes, where they start in
  # it, and their count.
  #: (value, ptr, ptr, bool) -> void
  def zr_capi_buffer_window(window, base, size, writing)
    bytes = zr_ary_at(window, 0)
    start = zr_fix2long(zr_ary_at(window, 1))
    at = Machine.ptr(0)
    if zr_fixnum_p(bytes)
      at = Machine.ptr(zr_fix2long(bytes)) + start
    elsif bytes != QNIL
      # The buffer said whether C may write (`c_window`); a String that
      # it holds is locked to it, so C's writes only drop what the String
      # knew of its characters.
      if writing
        zr_str_modified(bytes)
      end
      at = RString[bytes].ptr + start
    end
    Machine.store64(base, 0, Machine.word(at))
    Machine.store64(size, 0, zr_fix2long(zr_ary_at(window, 2)))
  end

  # rb_io_buffer_locked_for_reading and _for_writing: `callback(base,
  # size, argument)` over the bytes, with the buffer locked until it
  # returns or raises, as rb_ensure runs it.
  #: (value, ptr, value) -> value
  def rb_io_buffer_locked_for_reading(buffer, callback, argument)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_locked(buffer, callback, argument, false)
  end

  #: (value, ptr, value) -> value
  def rb_io_buffer_locked_for_writing(buffer, callback, argument)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_locked(buffer, callback, argument, true)
  end

  #: (value, ptr, value, bool) -> value
  def zr_capi_buffer_locked(buffer, callback, argument, writing)
    zr_capi_buffer_send(buffer, Machine.id(:c_hold), 1, zr_bool(writing), QNIL, QNIL, QNIL)
    argv = Machine.slot(24)
    zr_capi_buffer_bytes(buffer, argv, argv + 8, writing)
    Machine.store64(argv, 16, Machine.word(argument))
    r = Machine.value(zr_call_c(callback, argv, 3))
    left = Machine.value(QNIL)
    if r == QUNDEF
      zr_capi_park()
      left = Task[zr_task()].parked
      Task[zr_task()].parked = Machine.value(QNIL)
    end
    zr_capi_buffer_send(buffer, Machine.id(:c_unlock), 0, QNIL, QNIL, QNIL, QNIL)
    if r == QUNDEF
      Task[zr_task()].parked = left
      zr_capi_unpark()
      zr_c_unwind()
    end
    r
  end

  #: (value) -> value
  def rb_io_buffer_transfer(buffer)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:transfer), 0, QNIL, QNIL, QNIL, QNIL)
  end

  #: (value, word) -> void
  def rb_io_buffer_resize(buffer, size)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:resize), 1, zr_capi_unsigned(size), QNIL, QNIL, QNIL)
  end

  #: (value, word) -> void
  def rb_io_buffer_advance(buffer, amount)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:advance), 1, zr_capi_unsigned(amount), QNIL, QNIL, QNIL)
  end

  #: (value, i32, word, word) -> void
  def rb_io_buffer_clear(buffer, value, offset, length)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:clear), 3, zr_fix(Machine.sword(value) & 255), zr_capi_unsigned(offset), zr_capi_unsigned(length), QNIL)
  end

  # rb_io_buffer_read, _pread, _write and _pwrite: one transfer of at
  # most `length` bytes at `offset` in the buffer.
  #: (value, value, word, word) -> value
  def rb_io_buffer_read(buffer, io, offset, length)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:read), 3, io, zr_capi_unsigned(offset), zr_capi_unsigned(length), QNIL)
  end

  #: (value, value, word, word, word) -> value
  def rb_io_buffer_pread(buffer, io, from, offset, length)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:pread), 4, io, zr_c_result(zr_int_from_word(from)), zr_capi_unsigned(offset), zr_capi_unsigned(length))
  end

  #: (value, value, word, word) -> value
  def rb_io_buffer_write(buffer, io, offset, length)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:write), 3, io, zr_capi_unsigned(offset), zr_capi_unsigned(length), QNIL)
  end

  #: (value, value, word, word, word) -> value
  def rb_io_buffer_pwrite(buffer, io, from, offset, length)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_buffer_send(buffer, Machine.id(:pwrite), 4, io, zr_c_result(zr_int_from_word(from)), zr_capi_unsigned(offset), zr_capi_unsigned(length))
  end

  # `buffer.mid(a, b, c, d)` with the first `argc` arguments, through
  # IO::Buffer.c_call.
  #: (value, word, word, value, value, value, value) -> value
  def zr_capi_buffer_send(buffer, mid, argc, a, b, c, d)
    args = Machine.slot(48)
    Machine.store64(args, 0, Machine.word(buffer))
    Machine.store64(args, 8, Machine.word(zr_sym(mid)))
    Machine.store64(args, 16, Machine.word(a))
    Machine.store64(args, 24, Machine.word(b))
    Machine.store64(args, 32, Machine.word(c))
    Machine.store64(args, 40, Machine.word(d))
    zr_c_result(zr_send(zr_capi_buffer_class(), Machine.id(:c_call), argc + 2, args))
  end

  #: () -> value
  def zr_capi_buffer_class
    Machine.value(Machine.load64(Machine.global(:rb_cIOBuffer), 0))
  end

  # rb_cIOBuffer and its two kinds, and the sizes that C reads.
  #: () -> void
  def zr_capi_buffer_init
    buffer = zr_capi_nested(Machine.id(:IO), Machine.id(:Buffer))
    zr_capi_set(Machine.global(:rb_cIOBuffer), buffer)
    zr_capi_set(Machine.global(:rb_cIOBufferStorage), zr_capi_call1(buffer, Machine.id(:const_get), zr_sym(Machine.id(:Storage))))
    zr_capi_set(Machine.global(:rb_cIOBufferSlice), zr_capi_call1(buffer, Machine.id(:const_get), zr_sym(Machine.id(:Slice))))
    Machine.store64(Machine.global(:RUBY_IO_BUFFER_PAGE_SIZE), 0, zr_fix2long(zr_capi_call1(buffer, Machine.id(:const_get), zr_sym(Machine.id(:PAGE_SIZE)))))
    Machine.store64(Machine.global(:RUBY_IO_BUFFER_MAP_ALIGNMENT), 0, zr_fix2long(zr_capi_call1(buffer, Machine.id(:const_get), zr_sym(Machine.id(:MAP_ALIGNMENT)))))
    Machine.store64(Machine.global(:RUBY_IO_BUFFER_DEFAULT_SIZE), 0, zr_fix2long(zr_capi_call1(buffer, Machine.id(:const_get), zr_sym(Machine.id(:DEFAULT_SIZE)))))
  end
end
