# A growable byte buffer outside the arena, for building strings and
# messages.
Machine.struct :Buf, ptr: Ptr, len: Word, capa: Word

sig [Ptr] => Void
machine def zr_buf_init(b)
  Buf.set_ptr(b, zr_xmalloc(64))
  Buf.set_len(b, 0)
  Buf.set_capa(b, 64)
end

sig [Ptr, Word] => Void
machine def zr_buf_reserve(b, n)
  need = Buf.len(b) + n
  if need > Buf.capa(b)
    capa = Buf.capa(b) * 2
    if capa < need
      capa = need
    end
    p = zr_xmalloc(capa)
    zr_memcpy(p, Buf.ptr(b), Buf.len(b))
    free(Buf.ptr(b))
    Buf.set_ptr(b, p)
    Buf.set_capa(b, capa)
  end
end

sig [Ptr, Ptr, Word] => Void
machine def zr_buf_push(b, bytes, n)
  zr_buf_reserve(b, n)
  zr_memcpy(Buf.ptr(b) + Buf.len(b), bytes, n)
  Buf.set_len(b, Buf.len(b) + n)
end

sig [Ptr, Word] => Void
machine def zr_buf_byte(b, c)
  zr_buf_reserve(b, 1)
  Machine.store8(Buf.ptr(b) + Buf.len(b), 0, Machine.i8(c))
  Buf.set_len(b, Buf.len(b) + 1)
end

sig [Ptr, Word] => Void
machine def zr_buf_long(b, n)
  digits = Machine.slot(24)
  zr_buf_push(b, digits, zr_long_digits(n, digits))
end

sig [Ptr, Word] => Void
machine def zr_buf_sym(b, id)
  zr_buf_push(b, zr_symbol_name_ptr(id), zr_symbol_name_len(id))
end

# A String's bytes. Anything else is a bug in the kernel, and stops by
# name rather than read a String's fields out of it.
sig [Ptr, Value] => Void
machine def zr_buf_str(b, s)
  if zr_special_p(s) || (RBasic.flags(s) & T_MASK) != T_STRING
    zr_bug(Machine.bytes("zr_buf_str was given something that is not a String\n"), 53)
  end
  zr_buf_push(b, RString.ptr(s), RString.len(s))
end

# The buffer's bytes as a new String; the buffer is freed.
sig [Ptr] => Value
machine def zr_buf_take(b)
  s = zr_str_new(Buf.ptr(b), Buf.len(b))
  free(Buf.ptr(b))
  s
end
