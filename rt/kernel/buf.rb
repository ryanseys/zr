# A growable byte buffer for building strings and messages. It starts
# in the 64 bytes of its own tail, on the stack with the rest of it,
# and moves to malloc'd memory only when it grows past them: a message
# that raises and is never taken leaves nothing to free.
Machine.struct :BufTail, w0: Word, w1: Word, w2: Word, w3: Word, w4: Word, w5: Word, w6: Word, w7: Word
Machine.struct :Buf, ptr: Ptr, len: Word, capa: Word, tail: BufTail

sig [Ptr] => Void
machine def zr_buf_init(b)
  Buf.set_ptr(b, Buf.tail(b))
  Buf.set_len(b, 0)
  Buf.set_capa(b, BufTail.size)
end

# Whether the bytes still live in the buffer's own tail.
sig [Ptr] => Bool
machine def zr_buf_inline_p(b)
  Buf.ptr(b) == Buf.tail(b)
end

# The malloc'd bytes given back, when the buffer grew into any.
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

# A String's bytes. Anything else is a bug in the kernel, and stops by
# name rather than read a String's fields out of it.
sig [Ptr, Value] => Void
machine def zr_buf_str(b, s)
  if zr_special_p(s) || (RBasic.flags(s) & T_MASK) != T_STRING
    zr_bug(Machine.bytes("zr_buf_str was given something that is not a String\n"), 53)
  end
  zr_buf_push(b, RString.ptr(s), RString.len(s))
end

# The buffer's bytes as a new String, which takes the buffer itself.
#
# It used to hand the bytes to `zr_str_new`, which mallocs again and
# copies them, and then free the buffer -- two allocations and two
# copies for every `String#+` and every `"#{}"`. The buffer is already
# the right shape for an RString's payload, so the String takes it and
# the buffer gives it up. `capa` leaves out the byte the NUL sits in,
# which is what `zr_str_new` records and what `zr_str_concat` reads.
sig [Ptr] => Value
machine def zr_buf_take(b)
  n = Buf.len(b)
  if zr_buf_inline_p(b)
    # Bytes still in the tail are copied out: the String outlives the
    # frame the buffer sits in.
    p = zr_xmalloc(n + 1)
    zr_memcpy(p, Buf.ptr(b), n)
    Buf.set_ptr(b, p)
    Buf.set_capa(b, n + 1)
  end
  zr_buf_reserve(b, 1)
  p = Buf.ptr(b)
  Machine.store8(p + n, 0, Machine.i8(0))
  s = zr_alloc(T_STRING, zr_global(G_STRING))
  RString.set_ptr(s, p)
  RString.set_len(s, n)
  RString.set_capa(s, Buf.capa(b) - 1)
  Buf.set_ptr(b, 0)
  Buf.set_len(b, 0)
  Buf.set_capa(b, 0)
  s
end

# The buffer's bytes as a new String in `index` while they are plain
# ASCII, as the core library starts one it writes out of a name or an
# inspect. A byte past ASCII came from a piece in UTF-8, which the
# String then takes, as rb_str_buf_append has it.
sig [Ptr, Word] => Value
machine def zr_buf_take_at(b, index)
  ascii = zr_bytes_ascii_only_p(Buf.ptr(b), Buf.len(b))
  zr_str_set_index(zr_buf_take(b), ascii ? index : ENC_UTF8)
end
