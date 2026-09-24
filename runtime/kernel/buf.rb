# A growable byte buffer to build strings and messages. It starts in the
# 64 bytes of its own tail, on the stack with the rest of the buffer. It
# moves to malloc'd memory only when it grows past those bytes. Thus a
# message that raises before a String takes it leaves nothing to free.
Machine.struct :BufTail, w0: Word, w1: Word, w2: Word, w3: Word, w4: Word, w5: Word, w6: Word, w7: Word
Machine.struct :Buf, ptr: Ptr, len: Word, capa: Word, tail: BufTail

sig [Ptr] => Void
machine def zr_buf_init(b)
  Buf.set_ptr(b, Buf.tail(b))
  Buf.set_len(b, 0)
  Buf.set_capa(b, BufTail.size)
end

# Whether the bytes are still in the buffer's own tail.
sig [Ptr] => Bool
machine def zr_buf_inline_p(b)
  Buf.ptr(b) == Buf.tail(b)
end

# Frees the malloc'd bytes, if the buffer grew into any.
sig [Ptr] => Void
machine def zr_buf_free(b)
  if !zr_buf_inline_p(b)
    zr_xfree(Buf.ptr(b))
  end
  Buf.set_ptr(b, 0)
  Buf.set_len(b, 0)
  Buf.set_capa(b, 0)
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
    if !zr_buf_inline_p(b)
      zr_xfree(Buf.ptr(b))
    end
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

# Appends a String's bytes. Any other object is a bug in the kernel. It
# stops with a message, and does not read String fields from the object.
sig [Ptr, Value] => Void
machine def zr_buf_str(b, s)
  if zr_special_p(s) || (RBasic.flags(s) & T_MASK) != T_STRING
    zr_bug(Machine.bytes("zr_buf_str was given something that is not a String\n"), 53)
  end
  zr_buf_push(b, RString.ptr(s), RString.len(s))
end

# Returns the buffer's bytes as a new String that takes the buffer's
# memory. The buffer has the correct shape for an RString payload, so
# no second allocation or copy is necessary for each `String#+` and
# `"#{}"`. `capa` does not include the byte for the NUL, which agrees
# with `zr_str_new` and with what `zr_str_concat` reads.
sig [Ptr] => Value
machine def zr_buf_take(b)
  n = Buf.len(b)
  s = zr_alloc(T_STRING, zr_global(G_STRING), zr_str_cell_bytes(n))
  if n <= zr_str_embed_capa(s)
    # Copies bytes that fit in the cell, from the tail or from a grown
    # buffer. Then it frees the grown buffer.
    zr_str_buf_new(s, n)
    zr_memcpy(RString.ptr(s), Buf.ptr(b), n)
    zr_buf_free(b)
  else
    zr_buf_reserve(b, 1)
    RString.set_ptr(s, Buf.ptr(b))
    RString.set_capa(s, Buf.capa(b) - 1)
    Buf.set_ptr(b, 0)
    Buf.set_len(b, 0)
    Buf.set_capa(b, 0)
  end
  Machine.store8(RString.ptr(s) + n, 0, Machine.i8(0))
  RString.set_len(s, n)
  s
end

# Returns the buffer's bytes as a new String in encoding `index` while
# they are plain ASCII, as the core library does for a String it builds
# from a name or an inspect. A non-ASCII byte came from a UTF-8 piece,
# so the String then becomes UTF-8, as with rb_str_buf_append.
sig [Ptr, Word] => Value
machine def zr_buf_take_at(b, index)
  ascii = zr_bytes_ascii_only_p(Buf.ptr(b), Buf.len(b))
  zr_str_set_index(zr_buf_take(b), ascii ? index : ENC_UTF8)
end
