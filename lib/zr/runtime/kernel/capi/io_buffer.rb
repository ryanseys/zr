module Zr::Kern
  # The C API of IO::Buffer: the bytes of a buffer, which C reads or
  # writes in place, as io-event's selectors do.

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
    window = zr_capi_call1(buffer, Machine.id(:c_window), zr_bool(writing))
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
end
