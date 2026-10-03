module Zr::Kern
  # A growable byte buffer to build strings and messages. It starts in the
  # 64 bytes of its own tail, on the stack with the rest of the buffer. It
  # moves to malloc'd memory only when it grows past those bytes. Thus a
  # message that raises before a String takes it leaves nothing to free.
  class BufTail < Layout
    attr_accessor :w0 #: word
    attr_accessor :w1 #: word
    attr_accessor :w2 #: word
    attr_accessor :w3 #: word
    attr_accessor :w4 #: word
    attr_accessor :w5 #: word
    attr_accessor :w6 #: word
    attr_accessor :w7 #: word
  end

  class Buf < Layout
    attr_accessor :ptr #: ptr
    attr_accessor :len #: word
    attr_accessor :capa #: word
    attr_reader :tail #: BufTail
  end

  #: (ptr) -> void
  def zr_buf_init(b)
    Buf[b].ptr = Machine.ptr(Buf[b].tail)
    Buf[b].len = 0
    Buf[b].capa = BufTail.size
  end

  # Whether the bytes are still in the buffer's own tail.
  #: (ptr) -> bool
  def zr_buf_inline_p(b)
    Buf[b].ptr == Machine.ptr(Buf[b].tail)
  end

  # Frees the malloc'd bytes, if the buffer grew into any.
  #: (ptr) -> void
  def zr_buf_free(b)
    if !zr_buf_inline_p(b)
      zr_xfree(Buf[b].ptr)
    end
    Buf[b].ptr = 0
    Buf[b].len = 0
    Buf[b].capa = 0
  end

  #: (ptr, word) -> void
  def zr_buf_reserve(b, n)
    need = Buf[b].len + n
    if need > Buf[b].capa
      capa = Buf[b].capa * 2
      if capa < need
        capa = need
      end
      p = zr_xmalloc(capa)
      zr_memcpy(p, Buf[b].ptr, Buf[b].len)
      if !zr_buf_inline_p(b)
        zr_xfree(Buf[b].ptr)
      end
      Buf[b].ptr = p
      Buf[b].capa = capa
    end
  end

  #: (ptr, ptr, word) -> void
  def zr_buf_push(b, bytes, n)
    zr_buf_reserve(b, n)
    zr_memcpy(Buf[b].ptr + Buf[b].len, bytes, n)
    Buf[b].len = Buf[b].len + n
  end

  #: (ptr, word) -> void
  def zr_buf_byte(b, c)
    zr_buf_reserve(b, 1)
    Machine.store8(Buf[b].ptr + Buf[b].len, 0, Machine.i8(c))
    Buf[b].len = Buf[b].len + 1
  end

  #: (ptr, word) -> void
  def zr_buf_long(b, n)
    digits = Machine.slot(24)
    zr_buf_push(b, digits, zr_long_digits(n, digits))
  end

  #: (ptr, word) -> void
  def zr_buf_sym(b, id)
    zr_buf_push(b, zr_symbol_name_ptr(id), zr_symbol_name_len(id))
  end

  # Appends a String's bytes. Any other object is a bug in the kernel. It
  # stops with a message, and does not read String fields from the object.
  #: (ptr, value) -> void
  def zr_buf_str(b, s)
    if zr_special_p(s) || (RBasic[s].flags & T_MASK) != T_STRING
      zr_bug(Machine.bytes("zr_buf_str was given something that is not a String\n"), 53)
    end
    zr_buf_push(b, RString[s].ptr, RString[s].len)
  end

  # Returns the buffer's bytes as a new String that takes the buffer's
  # memory. The buffer has the correct shape for an RString payload, so
  # no second allocation or copy is necessary for each `String#+` and
  # `"#{}"`. `capa` does not include the byte for the NUL, which agrees
  # with `zr_str_new` and with what `zr_str_concat` reads.
  #: (ptr) -> value
  def zr_buf_take(b)
    n = Buf[b].len
    s = zr_alloc(T_STRING, zr_global(G_STRING), zr_str_cell_bytes(n))
    if n <= zr_str_embed_capa(s)
      # Copies bytes that fit in the cell, from the tail or from a grown
      # buffer. Then it frees the grown buffer.
      zr_str_buf_new(s, n)
      zr_memcpy(RString[s].ptr, Buf[b].ptr, n)
      zr_buf_free(b)
    else
      zr_buf_reserve(b, 1)
      RString[s].ptr = Buf[b].ptr
      RString[s].capa = Buf[b].capa - 1
      Buf[b].ptr = 0
      Buf[b].len = 0
      Buf[b].capa = 0
    end
    Machine.store8(RString[s].ptr + n, 0, Machine.i8(0))
    RString[s].len = n
    s
  end

  # Returns the buffer's bytes as a new String in encoding `index` while
  # they are plain ASCII, as the core library does for a String it builds
  # from a name or an inspect. A non-ASCII byte came from a UTF-8 piece,
  # so the String then becomes UTF-8, as with rb_str_buf_append.
  #: (ptr, word) -> value
  def zr_buf_take_at(b, index)
    ascii = zr_bytes_ascii_only_p(Buf[b].ptr, Buf[b].len)
    zr_str_set_index(zr_buf_take(b), ascii ? index : ENC_UTF8)
  end
end
