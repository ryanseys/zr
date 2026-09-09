# A growable byte buffer outside the arena, for building strings and
# messages.
Machine.struct :Buf, ptr: Ptr, len: Word, capa: Word

sig [Ptr] => Void
machine def zr_buf_init(b)
  Buf.set_ptr(b, malloc(64))
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
    p = malloc(capa)
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

sig [Ptr, Value] => Void
machine def zr_buf_str(b, s)
  zr_buf_push(b, RString.ptr(s), RString.len(s))
end

# The buffer's bytes as a new String; the buffer is freed.
sig [Ptr] => Value
machine def zr_buf_take(b)
  s = zr_str_new(Buf.ptr(b), Buf.len(b))
  free(Buf.ptr(b))
  s
end
