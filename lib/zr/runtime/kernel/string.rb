module Zr::Kern
  # Strings: a length, a capacity, and a buffer outside the arena.
  RString = layout basic: RBasic, len: Word, capa: Word, ptr: Ptr

  # A String whose bytes are in its own cell, after the header, with as
  # many bytes as the cell has room for, plus a NUL. A longer String keeps
  # its bytes in a malloc'd buffer of `capa` + 1 bytes. In both cases
  # `ptr` points to the bytes and `capa` gives the room, so a reader does
  # not need to know which. An Array keeps its elements the same way.
  FL_EMBED = 1 << 7
  FL_EMBED_CLEAR = 0 - FL_EMBED - 1

  sig [Value] => Bool
  def zr_str_embedded_p(s)
    (RBasic.flags(s) & FL_EMBED) != 0
  end

  # Returns the number of bytes that the cell of `s` has room for, not
  # counting the NUL: 23 in a 64-byte cell, 87 in 128, 215 in 256.
  sig [Value] => Word
  def zr_str_embed_capa(s)
    zr_cell_bytes(s) - RString.size - 1
  end

  # Returns the cell size for a String of `n` bytes: a cell that holds them
  # and the NUL, else the smallest cell, with the bytes malloc'd.
  sig [Word] => Word
  def zr_str_cell_bytes(n)
    bytes = RString.size + n + 1
    bytes <= CELL_MAX ? bytes : RString.size
  end

  # Gives `s` a buffer with room for `n` bytes and a NUL, and discards the
  # old bytes. The buffer is the tail of the cell when the bytes fit, else
  # a malloc'd buffer.
  sig [Value, Word] => Void
  def zr_str_buf_new(s, n)
    if n <= zr_str_embed_capa(s)
      RString.set_ptr(s, Machine.ptr(s) + RString.size)
      RString.set_capa(s, zr_str_embed_capa(s))
      RBasic.set_flags(s, (RBasic.flags(s) | FL_EMBED) & FL_GAP_CLEAR)
    else
      RString.set_ptr(s, zr_xmalloc(n + 1))
      RString.set_capa(s, n)
      RBasic.set_flags(s, RBasic.flags(s) & FL_EMBED_CLEAR & FL_GAP_CLEAR)
    end
  end

  # A malloc'd buffer can start after the start of its block: a shift off
  # the front (zr_str_shift_front) moves `ptr` forward and leaves the other
  # bytes where they are. These flag bits keep the size of that gap, so
  # the free gets the whole block back. `capa` counts from `ptr`.
  FL_GAP_SHIFT = 40
  FL_GAP_MAX = (1 << 22) - 1
  FL_GAP_CLEAR = 0 - (FL_GAP_MAX << FL_GAP_SHIFT) - 1

  sig [Value] => Word
  def zr_str_gap(s)
    (RBasic.flags(s) >> FL_GAP_SHIFT) & FL_GAP_MAX
  end

  # Frees the buffer when it is malloc'd. The tail of the cell is freed
  # with the cell.
  sig [Value] => Void
  def zr_str_buf_free(s)
    if !zr_str_embedded_p(s)
      gap = zr_str_gap(s)
      zr_sized_xfree(RString.ptr(s) - gap, RString.capa(s) + gap + 1)
    end
  end

  # Makes room for `n` bytes and a NUL, and keeps the bytes. A buffer that
  # grows leaves the cell, and after that it doubles each time.
  sig [Value, Word] => Void
  def zr_str_reserve(s, n)
    if n > RString.capa(s)
      zr_str_grow(s, n)
    end
  end
  # Most appends fit, so the test is in the writer's code.
  inline :zr_str_reserve

  sig [Value, Word] => Void
  def zr_str_grow(s, n)
    capa = RString.capa(s) * 2
    if capa < n
      capa = n
    end
    p = zr_xmalloc(capa + 1)
    zr_memcpy(p, RString.ptr(s), RString.len(s))
    zr_str_buf_free(s)
    RString.set_ptr(s, p)
    RString.set_capa(s, capa)
    RBasic.set_flags(s, RBasic.flags(s) & FL_EMBED_CLEAR & FL_GAP_CLEAR)
  end


  # A String whose bytes a scan found all below 0x80, which CRuby calls the
  # 7-bit coderange. Each write to the bytes clears it, so the runtime scans
  # a String that it reads many times only once.
  FL_ASCII = 1 << 21
  # A String that a scan found valid in its encoding, CRuby's valid
  # coderange. The same writes clear it, and so does a new encoding.
  FL_VALID = 1 << 23
  # A String whose bytes the ASCII scan read, whatever the result. With
  # FL_ASCII, the bytes are all below 0x80. Without it, one byte is not.
  # FL_ASCII alone records only a scan that succeeded, so without this flag
  # a text with one non-ASCII byte gets a new scan for each check, for
  # example each Regexp match on it. Each write to the bytes clears it, and
  # so does an encoding that cannot hold ASCII text. (Bits 24 to 31 hold
  # the encoding, FL_ENC_SHIFT, and bit 32 is FL_SNAPSHOT; this bit is
  # above them.)
  FL_SCANNED = 1 << 33
  FL_ASCII_CLEAR = 0 - FL_ASCII - FL_SCANNED - 1
  # A String whose frozen copy MatchData keeps (MatchData.snapshot) and that
  # is still equal to the copy: nothing changed it since. Each change clears
  # it. Each change also calls the frozen check first (zr_modify_frozen_p),
  # which clears it too, before a byte changes. Bits 24 to 31 hold the
  # encoding (FL_ENC_SHIFT); no bit above them is in use.
  FL_SNAPSHOT = 1 << 32
  FL_SNAPSHOT_CLEAR = 0 - FL_SNAPSHOT - 1
  FL_SCANS_CLEAR = 0 - FL_ASCII - FL_VALID - FL_SNAPSHOT - FL_SCANNED - 1

  # The bytes of `s` changed, so the scan results for them are not valid.
  sig [Value] => Void
  def zr_str_modified(s)
    RBasic.set_flags(s, RBasic.flags(s) & FL_SCANS_CLEAR)
  end

  # Whether `s` did not change since MatchData.snapshot last copied it.
  sig [Value] => Value
  def zr_str_snapshot_p(s)
    zr_bool((RBasic.flags(s) & FL_SNAPSHOT) != 0)
  end

  sig [Value] => Value
  def zr_str_snapshot_set(s)
    RBasic.set_flags(s, RBasic.flags(s) | FL_SNAPSHOT)
    s
  end

  sig [Ptr, Word] => Value
  def zr_str_new(bytes, len)
    s = zr_alloc(T_STRING, zr_global(G_STRING), zr_str_cell_bytes(len))
    zr_str_buf_new(s, len)
    zr_memcpy(RString.ptr(s), bytes, len)
    Machine.store8(RString.ptr(s) + len, 0, Machine.i8(0))
    RString.set_len(s, len)
    s
  end

  # `String#initialize(source)`: copies the bytes and encoding of the
  # source into the receiver. A nil source leaves the receiver empty.
  sig [Value, Value] => Value
  def zr_str_initialize_m(recv, src)
    if src == QNIL
      return recv
    end
    if zr_special_p(src) || zr_type(src) != T_STRING
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      zr_buf_class_of(b, src)
      zr_buf_push(b, Machine.bytes(" into String"), 12)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    zr_str_take_bytes(recv, src)
    zr_str_modified(recv)
    zr_str_copy_encoding(recv, src)
  end

  # Puts the bytes of `src` in place of the bytes of `recv`, in a buffer of
  # their size. If `src` is `recv`, nothing changes.
  sig [Value, Value] => Void
  def zr_str_take_bytes(recv, src)
    if Machine.word(recv) == Machine.word(src)
      return
    end
    n = RString.len(src)
    zr_str_buf_free(recv)
    zr_str_buf_new(recv, n)
    zr_memcpy(RString.ptr(recv), RString.ptr(src), n)
    Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
    RString.set_len(recv, n)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_initialize(recv, argc, argv, cref, blk)
    if argc > 1
      return zr_wrong_arity_range(argc, 0, 1)
    end
    zr_str_initialize_m(recv, argc == 1 ? Machine.value(Machine.load64(argv, 0)) : Machine.value(QNIL))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_to_s(recv, argc, argv, cref, blk)
    if zr_real_class(recv) != zr_global(G_STRING)
      return zr_str_new(RString.ptr(recv), RString.len(recv))
    end
    recv
  end

  G_FROZEN_ERROR = 27

  sig [Value] => Bool
  def zr_frozen_p(v)
    if zr_special_p(v)
      return true
    end
    (RBasic.flags(v) & FL_FREEZE) != 0
  end

  # Raises `can't modify frozen String: "abc"`.
  sig [Value] => Value
  def zr_frozen_error(v)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("can't modify frozen "), 20)
    zr_buf_class_of(b, v)
    zr_buf_push(b, Machine.bytes(": "), 2)
    # An `inspect` that writes to its own frozen receiver comes back here for
    # the same object. That second error shows ` ...` and does not call
    # inspect again (rb_error_frozen_object runs inspect_frozen_obj under
    # rb_exec_recursive).
    if zr_guard_enter(v, Machine.id(:__frozen_error__))
      zr_buf_push(b, Machine.bytes(" ..."), 4)
    else
      s = zr_inspect(v)
      zr_guard_leave(v, Machine.id(:__frozen_error__))
      if s == QUNDEF
        zr_buf_free(b)
        return s
      end
      zr_buf_str(b, s)
    end
    e = zr_exc_new(zr_global(G_FROZEN_ERROR), zr_buf_take(b))
    zr_exc_detail(e, Machine.id(:receiver), v)
    zr_raise(e)
  end

  # Returns the String operand of a String method: a String, or the result
  # of `to_str`, else raises CRuby's TypeError.
  sig [Value] => Value
  def zr_str_operand(v)
    if zr_special_p(v) || zr_type(v) != T_STRING
      if !zr_special_p(v) && zr_find_method(zr_class_of(v), Machine.id(:to_str)) != 0
        s = zr_send(v, Machine.id(:to_str), 0, 0)
        return s if s == QUNDEF
        if !zr_special_p(s) && zr_type(s) == T_STRING
          return s
        end
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("can't convert "), 14)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes(" to String ("), 12)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes("#to_str gives "), 14)
        zr_buf_class_of(b, s)
        zr_buf_push(b, Machine.bytes(")"), 1)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      if v == QNIL || v == QTRUE || v == QFALSE
        s = zr_inspect(v)
        return s if s == QUNDEF
        zr_buf_str(b, s)
      else
        zr_buf_class_of(b, v)
      end
      zr_buf_push(b, Machine.bytes(" into String"), 12)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    v
  end

  # Returns the encoding of `s`: ruby's own index into `Encoding.list`.
  sig [Value] => Word
  def zr_str_encoding_index(s)
    i = (RBasic.flags(s) >> FL_ENC_SHIFT) & 255
    i < 2 ? 1 - i : i
  end

  sig [Value, Word] => Value
  def zr_str_set_index(s, index)
    i = index < 2 ? 1 - index : index
    flags = (RBasic.flags(s) & FL_ENC_KEEP & (0 - FL_VALID - 1)) | (i << FL_ENC_SHIFT)
    # ASCII bytes are not ASCII text in UTF-16 or UTF-32.
    if !zr_enc_ascii_compat_p(index)
      flags = flags & FL_ASCII_CLEAR
    end
    RBasic.set_flags(s, flags)
    s
  end
  # Each append sets the receiver's encoding again.
  inline :zr_str_set_index

  # Copies the encoding of `src` to `s`.
  sig [Value, Value] => Value
  def zr_str_copy_encoding(s, src)
    zr_str_set_index(s, zr_str_encoding_index(src))
  end

  # Whether the String encodes its characters as UTF-8 does: in UTF-8, or
  # in UTF8-MAC or a carrier's UTF-8, which differ from UTF-8 only in the
  # characters that they convert.
  sig [Value] => Bool
  def zr_str_wide_p(s)
    index = zr_str_encoding_index(s)
    index == ENC_UTF8 || zr_enc_utf8_like_p(index)
  end

  # Whether the String is in one of the multibyte encodings of
  # lib/zr/runtime/kernel/enc_mb.rb, each of which has its own byte rules for
  # characters.
  sig [Value] => Bool
  def zr_str_mb_p(s)
    zr_enc_mb_p(zr_str_encoding_index(s))
  end

  # Returns the byte length of the character at byte `off` of a multibyte
  # String, or 0 when those bytes are not a whole character: a lead byte
  # that the encoding does not use, a byte that cannot follow it, or a
  # character that the text ends in the middle of.
  sig [Value, Word] => Word
  def zr_str_mb_len(s, off)
    p = RString.ptr(s) + off
    if Machine.u8(Machine.load8(p, 0)) < 128
      return 1
    end
    n = zr_onig_precise_len(zr_enc_mb_descriptor(zr_str_encoding_index(s)), p, RString.ptr(s) + RString.len(s))
    n > 0 ? n : 0
  end

  # rb_enc_precise_mbclen over bytes `from` up to `to` of a multibyte
  # String. Returns the length of the character, -1 for bytes that make no
  # character, or less than -1 when the bytes stop inside a character.
  sig [Value, Value, Value] => Value
  def zr_str_mb_precise_len_m(s, from, to)
    p = RString.ptr(s)
    zr_fix(zr_onig_precise_len(zr_enc_mb_descriptor(zr_str_encoding_index(s)), p + zr_fix2long(from), p + zr_fix2long(to)))
  end

  # rb_enc_mbmaxlen of the encoding of a multibyte String.
  sig [Value] => Value
  def zr_str_mb_max_len_m(s)
    zr_fix(OnigEnc.max_len(Machine.ptr(zr_enc_mb_descriptor(zr_str_encoding_index(s)))))
  end

  # Raises the error for a String whose bytes make no character. Encoding
  # writes the message, because the encoding names are there.
  sig [Value] => Value
  def zr_str_bad_bytes(s)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(s))
    zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:invalid_bytes), 1, slot)
  end

  # Whether an ASCII byte is an ASCII character in the encoding `index`.
  # This is true in all encodings but UTF-16 and UTF-32, dummy encodings
  # included.
  sig [Word] => Bool
  def zr_enc_ascii_compat_p(index)
    (index < ENC_UTF16BE || index > ENC_UTF32) && !zr_enc_dummy_p(index)
  end

  # The dummy encodings other than UTF-16 and UTF-32, by ruby's numbers:
  # IBM037, ISO-2022-JP, ISO-2022-JP-2, CP50220, CP50221, UTF-7 and
  # ISO-2022-JP-KDDI. None is ASCII-compatible, as in ruby.
  sig [Word] => Bool
  def zr_enc_dummy_p(index)
    index == 78 || (index >= 85 && index <= 88) || index == 94 || index == 99
  end

  # Returns the code unit width of UTF-16 (2) and UTF-32 (4), the Unicode
  # encodings that a String walks by units. Returns 0 for all others.
  sig [Value] => Word
  def zr_str_unit(s)
    i = zr_str_encoding_index(s)
    if i == ENC_UTF16BE || i == ENC_UTF16LE
      return 2
    end
    if i == ENC_UTF32BE || i == ENC_UTF32LE
      return 4
    end
    0
  end

  sig [Value] => Value
  def zr_str_unit_m(s)
    zr_fix(zr_str_unit(s))
  end

  sig [Value] => Value
  def zr_str_mb_p_m(s)
    zr_bool(zr_str_mb_p(s))
  end

  # Marks the bytes of the String as valid without a scan, as CRuby sets a
  # coderange that it copies from another String.
  sig [Value] => Value
  def zr_str_mark_valid_m(s)
    RBasic.set_flags(s, RBasic.flags(s) | FL_VALID)
    s
  end

  # Returns the code unit at byte `off`, read in the byte order of the String.
  sig [Value, Word, Word] => Word
  def zr_str_unit_at(s, off, unit)
    i = zr_str_encoding_index(s)
    big = i == ENC_UTF16BE || i == ENC_UTF32BE
    v = 0
    k = 0
    while k < unit
      at = big ? k : unit - 1 - k
      v = (v << 8) | Machine.u8(Machine.load8(RString.ptr(s) + off + at, 0))
      k += 1
    end
    v
  end

  # Returns the byte length of the character at byte `off` of a UTF-16 or
  # UTF-32 String: one code unit, a surrogate pair in UTF-16, or the
  # remaining bytes when they are fewer.
  sig [Value, Word, Word] => Word
  def zr_unit_char_len(s, off, unit)
    rest = RString.len(s) - off
    if rest < unit
      return rest
    end
    if unit == 2 && rest >= 4
      high = zr_str_unit_at(s, off, 2)
      if high >= 55296 && high <= 56319
        low = zr_str_unit_at(s, off + 2, 2)
        if low >= 56320 && low <= 57343
          return 4
        end
      end
    end
    unit
  end

  # Whether that character is whole: no lone surrogate, no UTF-32 unit
  # past Unicode, and no short tail.
  sig [Value, Word, Word, Word] => Bool
  def zr_unit_char_valid_p(s, off, len, unit)
    if len < unit
      return false
    end
    if len == 4 && unit == 2
      return true
    end
    v = zr_str_unit_at(s, off, unit)
    (v < 55296 || v > 57343) && v <= 1114111
  end

  # Returns the code point of a whole character.
  sig [Value, Word, Word, Word] => Word
  def zr_unit_point(s, off, len, unit)
    if unit == 2 && len == 4
      high = zr_str_unit_at(s, off, 2)
      low = zr_str_unit_at(s, off + 2, 2)
      return 65536 + ((high - 55296) << 10) + (low - 56320)
    end
    zr_str_unit_at(s, off, unit)
  end

  sig [Ptr, Word] => Void
  def zr_buf_unit_name(b, index)
    if index == ENC_UTF16BE
      zr_buf_push(b, Machine.bytes("UTF-16BE"), 8)
    elsif index == ENC_UTF16LE
      zr_buf_push(b, Machine.bytes("UTF-16LE"), 8)
    elsif index == ENC_UTF32BE
      zr_buf_push(b, Machine.bytes("UTF-32BE"), 8)
    else
      zr_buf_push(b, Machine.bytes("UTF-32LE"), 8)
    end
  end

  # `clear`, and `String#initialize` with a capacity and no source: removes
  # all bytes and keeps the encoding of the String.
  sig [Value] => Value
  def zr_str_discard(s)
    if zr_modify_frozen_p(s)
      return zr_frozen_error(s)
    end
    RString.set_len(s, 0)
    Machine.store8(RString.ptr(s), 0, Machine.i8(0))
    zr_str_modified(s)
    s
  end

  sig [Value] => Value
  def zr_str_set_binary(s)
    zr_str_set_index(s, ENC_BINARY)
  end

  sig [Value] => Value
  def zr_str_encoding_index_m(s)
    zr_fix(zr_str_encoding_index(s))
  end

  sig [Value, Value] => Value
  def zr_str_set_index_m(s, index)
    zr_str_set_index(s, zr_fix2long(index))
  end

  # Returns a String of plain ASCII that the core library writes (digits, a
  # name, brackets). It is US-ASCII, as rb_usascii_str_new makes it.
  sig [Ptr, Word] => Value
  def zr_usascii_str_new(bytes, len)
    zr_str_set_index(zr_str_new(bytes, len), ENC_USASCII)
  end

  # Tags `s` as US-ASCII, for text that the core library knows is plain ASCII.
  sig [Value] => Value
  def zr_str_usascii(s)
    zr_str_set_index(s, ENC_USASCII)
  end

  # Returns the encoding of a String after a piece is appended to it, as
  # rb_enc_cr_str_buf_cat decides. The String is `len` bytes in `index`, all
  # ASCII when `ascii` is true. The piece is in `piece`, all ASCII when
  # `piece_ascii` is true, and has at least one byte. Returns ENC_NONE when
  # the two cannot join.
  sig [Word, Bool, Word, Word, Bool] => Word
  def zr_enc_append(index, ascii, len, piece, piece_ascii)
    if piece == index
      return index
    end
    if !zr_enc_ascii_compat_p(index) || !zr_enc_ascii_compat_p(piece)
      return len == 0 ? piece : ENC_NONE
    end
    if piece_ascii
      return index
    end
    ascii ? piece : ENC_NONE
  end

  # The same for a String piece. An empty piece does not change the encoding.
  sig [Word, Bool, Word, Value] => Word
  def zr_enc_append_str(index, ascii, len, s)
    if RString.len(s) == 0 || zr_str_encoding_index(s) == index
      return index
    end
    zr_enc_append(index, ascii, len, zr_str_encoding_index(s), zr_str_ascii_bytes_p(s))
  end

  # Returns the encoding of a join, as rb_enc_compatible decides. An empty
  # side yields to the other, unless the receiver is empty and the other
  # side is not ASCII that the receiver's encoding can hold. Otherwise the
  # side that is not plain ASCII wins. When both sides are plain ASCII, the
  # receiver's encoding wins, so `"a" + "b".b` stays text.
  sig [Value, Value] => Word
  def zr_str_join_index(a, b)
    ia = zr_str_encoding_index(a)
    if ia == zr_str_encoding_index(b) || RString.len(b) == 0
      return ia
    end
    if RString.len(a) == 0
      return zr_enc_ascii_compat_p(ia) && zr_str_ascii_bytes_p(b) ? ia : zr_str_encoding_index(b)
    end
    zr_str_ascii_bytes_p(b) ? ia : zr_str_encoding_index(b)
  end
  # The two joins checks run at each append; most join one encoding.
  inline :zr_str_join_index

  # Whether a join of `a` and `b` is ruby's compatibility error: two
  # different encodings, neither side empty, and either one side in UTF-16
  # or UTF-32 or a non-ASCII byte on each side.
  sig [Value, Value] => Bool
  def zr_str_join_incompatible_p(a, b)
    ia = zr_str_encoding_index(a)
    ib = zr_str_encoding_index(b)
    if ia == ib || RString.len(a) == 0 || RString.len(b) == 0
      return false
    end
    if !zr_enc_ascii_compat_p(ia) || !zr_enc_ascii_compat_p(ib)
      return true
    end
    !zr_str_ascii_bytes_p(a) && !zr_str_ascii_bytes_p(b)
  end
  inline :zr_str_join_incompatible_p

  # Raises the error, with the encoding of the receiver first. Encoding
  # has the names, so it writes the message.
  sig [Value, Value] => Value
  def zr_str_join_incompatible(a, b)
    klass = zr_core_class(Machine.id(:Encoding))
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(a))
    Machine.store64(slot, 8, Machine.word(b))
    zr_send(klass, Machine.id(:incompatible), 2, slot)
  end

  # Whether each byte of `s` is below 0x80. It scans once and keeps the
  # result in FL_ASCII under FL_SCANNED, for both results.
  sig [Value] => Bool
  def zr_str_ascii_bytes_p(s)
    flags = RBasic.flags(s)
    if (flags & FL_ASCII) != 0
      return true
    end
    if (flags & FL_SCANNED) != 0
      return false
    end
    if !zr_enc_ascii_compat_p(zr_str_encoding_index(s))
      return false
    end
    n = RString.len(s)
    p = RString.ptr(s)
    i = 0
    # Eight bytes at a time: one of them has its high bit set, or none has.
    while i + 8 <= n && (Machine.load64(p + i, 0) & Machine.word(0x8080808080808080)) == 0
      i += 8
    end
    while i < n && Machine.u8(Machine.load8(p + i, 0)) < 128
      i += 1
    end
    if i < n
      RBasic.set_flags(s, flags | FL_SCANNED)
      return false
    end
    RBasic.set_flags(s, flags | FL_SCANNED | FL_ASCII)
    true
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_plus(recv, argc, argv, cref, blk)
    other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
    return other if other == QUNDEF
    if zr_str_join_incompatible_p(recv, other)
      return zr_str_join_incompatible(recv, other)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_str(b, recv)
    zr_buf_str(b, other)
    index = zr_str_join_index(recv, other)
    zr_str_set_index(zr_buf_take(b), index)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_times(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
    return r if r == QUNDEF
    n = Machine.load64(out, 0)
    if n < 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative argument"), 17)
    end
    # Checks the size of the copies before it makes any of them.
    if n != 0 && (9223372036854775807 / n) < RString.len(recv)
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("argument too big"), 16)
    end
    total = n * RString.len(recv)
    # A size no allocator can supply is a NoMemoryError the program can
    # rescue, not the end of the process. Only a large one is tried.
    if total > 268435456 && zr_memory_for_p(zr_fix(total)) == QFALSE
      return zr_no_memory()
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if total > 0
      # As rb_str_times: one copy, then the copied bytes again until the
      # whole length, so the copies number the log of `n`, not `n`.
      zr_buf_str(b, recv)
      zr_buf_reserve(b, total - Buf.len(b))
      while Buf.len(b) < total
        chunk = Buf.len(b) <= total - Buf.len(b) ? Buf.len(b) : total - Buf.len(b)
        zr_memcpy(Buf.ptr(b) + Buf.len(b), Buf.ptr(b), chunk)
        Buf.set_len(b, Buf.len(b) + chunk)
      end
    end
    zr_str_copy_encoding(zr_buf_take(b), recv)
  end

  # Appends an Integer as a character: a byte of a binary string, or a
  # UTF-8 sequence of a text string.
  sig [Value, Word] => Value
  def zr_str_concat_codepoint(recv, c)
    if zr_str_unit(recv) != 0
      # UTF-16 and UTF-32 encode a code point in Ruby code, which knows the
      # code units and their byte order.
      arg = Machine.slot(8)
      Machine.store64(arg, 0, Machine.word(zr_fix(c)))
      return zr_send(recv, Machine.id(:append_unit_point), 1, arg)
    end
    # A multibyte encoding encodes a code point in Ruby code, which has its
    # tables. So does UTF-8 under a different name, which an error message
    # gives.
    if zr_enc_mb_p(zr_str_encoding_index(recv)) || zr_enc_utf8_like_p(zr_str_encoding_index(recv))
      arg = Machine.slot(8)
      Machine.store64(arg, 0, Machine.word(zr_fix(c)))
      return zr_send(recv, Machine.id(:append_mb_point), 1, arg)
    end
    limit = zr_str_wide_p(recv) ? 1114111 : 255
    if zr_str_wide_p(recv) && c >= 55296 && c <= 57343
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("invalid codepoint 0x"), 20)
      shift = 12
      while shift >= 0
        digit = (c >> shift) & 15
        zr_buf_byte(b, digit < 10 ? 48 + digit : 55 + digit)
        shift -= 4
      end
      zr_buf_push(b, Machine.bytes(" in UTF-8"), 9)
      return zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b)
    end
    if c < 0 || c > limit
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_long(b, c)
      zr_buf_push(b, Machine.bytes(" out of char range"), 18)
      return zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b)
    end
    # A non-ASCII byte makes a US-ASCII String binary, as in rb_str_concat.
    # A frozen String raises before its encoding changes.
    if c > 127 && zr_str_encoding_index(recv) == ENC_USASCII
      if zr_modify_frozen_p(recv)
        return zr_frozen_error(recv)
      end
      zr_str_set_binary(recv)
    end
    # Writes one byte directly onto a String whose characters are bytes. A
    # separate String for the one byte costs a cell, a malloc and a copy, and
    # `out << byte` is how a program writes bytes: `Array#pack` writes each
    # byte of each integer that way, which is four cells for an `L<` and
    # eight for a `Q<`. The flags follow the rule of zr_str_concat: plain
    # ASCII onto plain ASCII stays plain ASCII. The encoding cannot change,
    # because zr_str_join_index returns the receiver's own encoding for a
    # piece in that encoding.
    if c < 128 || !zr_str_wide_p(recv)
      n = RString.len(recv) + 1
      zr_str_reserve(recv, n)
      Machine.store8(RString.ptr(recv) + n - 1, 0, Machine.i8(c))
      RString.set_len(recv, n)
      Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
      if c >= 128 || (RBasic.flags(recv) & FL_ASCII) == 0
        zr_str_modified(recv)
      end
      return recv
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if c < 2048
      zr_buf_byte(b, 192 | (c >> 6))
      zr_buf_byte(b, 128 | (c & 63))
    elsif c < 65536
      zr_buf_byte(b, 224 | (c >> 12))
      zr_buf_byte(b, 128 | ((c >> 6) & 63))
      zr_buf_byte(b, 128 | (c & 63))
    else
      zr_buf_byte(b, 240 | (c >> 18))
      zr_buf_byte(b, 128 | ((c >> 12) & 63))
      zr_buf_byte(b, 128 | ((c >> 6) & 63))
      zr_buf_byte(b, 128 | (c & 63))
    end
    s = zr_str_copy_encoding(zr_buf_take(b), recv)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(s))
    zr_str_concat(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  # Appends the bytes of `other` to `recv`, whatever the encoding of each.
  # The write buffer of an IO takes text as bytes.
  sig [Value, Value] => Value
  def zr_str_cat_bytes(recv, other)
    n = RString.len(recv) + RString.len(other)
    zr_str_reserve(recv, n)
    zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
    RString.set_len(recv, n)
    Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
    zr_str_modified(recv)
    recv
  end

  # Appends `len` bytes of `other` from byte `from` to `recv`, another
  # String, with no String between: `gsub` joins the text between its
  # matches this way.
  sig [Value, Value, Value, Value] => Value
  def zr_str_cat_range(recv, other, from, len)
    count = zr_fix2long(len)
    n = RString.len(recv) + count
    zr_str_reserve(recv, n)
    zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other) + zr_fix2long(from), count)
    RString.set_len(recv, n)
    Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
    zr_str_modified(recv)
    recv
  end

  # The integer directives of Array#pack and String#unpack for machine
  # words: `size` bytes (1, 2, 4 or 8) for each integer, most significant
  # first when `big` is true. lib/zr/runtime/core/pack.rb does all other elements
  # and directives, and calls these for the rest.

  # Appends at most `n` elements of the Array `items`, from `at`, to the
  # String `out` in two's complement, while each element is a fixnum.
  # Returns the number of elements done. The caller packs the rest, which
  # can convert through to_int or be a bignum.
  sig [Value, Value, Value, Value, Value, Value] => Value
  def zr_pack_ints(out, items, at, n, size, big)
    from = zr_fix2long(at)
    count = zr_fix2long(n)
    width = zr_fix2long(size)
    i = 0
    while i < count && zr_fixnum_p(Machine.value(Machine.load64(RArray.ptr(items) + ((from + i) * 8), 0)))
      i += 1
    end
    len = RString.len(out)
    zr_str_reserve(out, len + (i * width))
    p = RString.ptr(out) + len
    j = 0
    while j < i
      v = zr_fix2long(Machine.value(Machine.load64(RArray.ptr(items) + ((from + j) * 8), 0)))
      k = 0
      while k < width
        if big == QTRUE
          Machine.store8(p + (width - 1 - k), 0, Machine.i8(v & 255))
        else
          Machine.store8(p + k, 0, Machine.i8(v & 255))
        end
        v = v >> 8
        k += 1
      end
      p += width
      j += 1
    end
    RString.set_len(out, len + (i * width))
    Machine.store8(RString.ptr(out) + RString.len(out), 0, Machine.i8(0))
    zr_str_modified(out)
    zr_fix(i)
  end

  # Reads `n` integers from byte `at` of the String `bytes` onto the Array
  # `out`, in two's complement when `signed` is true. A slot that the
  # String ends inside gives nil, as CRuby's unpack gives for one past the
  # end.
  sig [Value, Value, Value, Value, Value, Value, Value] => Value
  def zr_unpack_ints(out, bytes, at, n, size, signed, big)
    from = zr_fix2long(at)
    count = zr_fix2long(n)
    width = zr_fix2long(size)
    i = 0
    while i < count
      start = from + (i * width)
      if start + width > RString.len(bytes)
        zr_ary_push(out, Machine.value(QNIL))
      else
        p = RString.ptr(bytes) + start
        v = 0
        k = 0
        while k < width
          # The bytes of a word: the eighth byte fills the sign bit.
          if big == QTRUE
            v = Machine.shl_wrap(v, 8) | Machine.u8(Machine.load8(p + k, 0))
          else
            v = Machine.shl_wrap(v, 8) | Machine.u8(Machine.load8(p + (width - 1 - k), 0))
          end
          k += 1
        end
        if width < 8
          if signed == QTRUE && v >= (1 << ((width * 8) - 1))
            v -= 1 << (width * 8)
          end
          zr_ary_push(out, zr_fix(v))
        elsif signed == QTRUE || v >= 0
          zr_ary_push(out, zr_int_from_word(v))
        else
          pair = Machine.slot(16)
          Machine.store64(pair, 0, Machine.word(zr_fix((v >> 32) & 4294967295)))
          Machine.store64(pair, 8, Machine.word(zr_fix(v & 4294967295)))
          zr_ary_push(out, zr_send(zr_global(G_INTEGER), Machine.id(:big_from_word), 2, pair))
        end
      end
      i += 1
    end
    out
  end

  # `<<` appends in place. A frozen receiver raises.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_concat(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    if zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
      return zr_str_concat_codepoint(recv, zr_fix2long(Machine.value(Machine.load64(argv, 0))))
    end
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_STRING
      other = zr_str_operand(other)
      return other if other == QUNDEF
    end
    if zr_str_join_incompatible_p(recv, other)
      return zr_str_join_incompatible(recv, other)
    end
    index = zr_str_join_index(recv, other)
    # Plain ASCII onto plain ASCII stays plain ASCII. The code scans the
    # piece when the receiver is known ASCII: a scan of the piece costs the
    # same as its copy, and without the flag the next join scans all of the
    # receiver.
    ascii = (RBasic.flags(recv) & FL_ASCII) != 0 && zr_str_ascii_bytes_p(other)
    n = RString.len(recv) + RString.len(other)
    zr_str_reserve(recv, n)
    zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
    RString.set_len(recv, n)
    Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
    if !ascii
      zr_str_modified(recv)
    end
    zr_str_set_index(recv, index)
    recv
  end

  # `concat`: appends the arguments in order, as `<<` appends one. It joins
  # two or more arguments first, as CRuby does, so `s.concat(s, s)` appends
  # `s` as it was and a bad argument appends nothing.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_concat_m(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    if argc < 2
      return argc == 0 ? recv : zr_str_concat(recv, argc, argv, cref, blk)
    end
    joined = zr_str_new(Machine.bytes(""), 0)
    zr_str_set_index(joined, zr_str_encoding_index(recv))
    i = 0
    while i < argc
      r = zr_str_concat(joined, 1, argv + (i * 8), cref, blk)
      return r if r == QUNDEF
      i += 1
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(joined))
    zr_str_concat(recv, 1, slot, cref, blk)
  end

  # Compares two byte strings bytewise; on a shared prefix, the shorter is
  # first. Returns -1, 0 or 1. It compares eight bytes at a time. The words
  # are little-endian, so in two words that differ, the first different
  # byte is the lowest, and its bit is the lowest bit set in their
  # difference.
  sig [Ptr, Word, Ptr, Word] => Word
  def zr_bytes_cmp(a, alen, b, blen)
    n = alen < blen ? alen : blen
    i = 0
    while i + 8 <= n
      x = Machine.load64(a + i, 0)
      y = Machine.load64(b + i, 0)
      if x != y
        k = Machine.ctz(x ^ y) & 56
        return ((x >> k) & 255) < ((y >> k) & 255) ? 0 - 1 : 1
      end
      i += 8
    end
    while i < n
      x = Machine.u8(Machine.load8(a + i, 0))
      y = Machine.u8(Machine.load8(b + i, 0))
      if x != y
        return x < y ? 0 - 1 : 1
      end
      i += 1
    end
    if alen == blen
      return 0
    end
    alen < blen ? 0 - 1 : 1
  end

  # `String#<=>`: bytewise, and nil for any other type.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_cmp(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_STRING
      return zr_str_cmp_other(recv, other)
    end
    r = zr_bytes_cmp(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other))
    if r != 0 || zr_str_comparable(recv, other)
      return zr_fix(r)
    end
    a = zr_str_encoding_index(recv)
    b = zr_str_encoding_index(other)
    zr_fix(a < b ? 0 - 1 : 1)
  end

  # rb_str_cmp_m for an operand that is not a String. If the operand has
  # `to_str`, the result of `to_str` compares. Otherwise the code calls the
  # operand's own `<=>` with the receiver and inverts the result, as
  # rb_invcmp does.
  sig [Value, Value] => Value
  def zr_str_cmp_other(recv, other)
    slot = Machine.slot(8)
    if !zr_special_p(other) && zr_find_method(zr_class_of(other), Machine.id(:to_str)) != 0
      s = zr_send(other, Machine.id(:to_str), 0, 0)
      return s if s == QUNDEF
      if !zr_special_p(s) && zr_type(s) == T_STRING
        Machine.store64(slot, 0, Machine.word(s))
        return zr_str_cmp(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
      end
      # rb_check_string_type: a to_str that gives neither a String nor
      # nil is an error.
      if s != QNIL
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("can't convert "), 14)
        zr_buf_class_of(b, other)
        zr_buf_push(b, Machine.bytes(" to String ("), 12)
        zr_buf_class_of(b, other)
        zr_buf_push(b, Machine.bytes("#to_str gives "), 14)
        zr_buf_class_of(b, s)
        zr_buf_push(b, Machine.bytes(")"), 1)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
    end
    Machine.store64(slot, 0, Machine.word(recv))
    r = zr_send(other, Machine.id(:<=>), 1, slot)
    if r == QUNDEF || r == QNIL
      return r
    end
    sign = zr_cmpint(r, other, recv)
    return sign if sign == QUNDEF
    zr_fix(0 - zr_fix2long(sign))
  end

  # Two strings compare only when they have the same encoding, or when both
  # are all ASCII.
  sig [Value, Value] => Bool
  def zr_str_comparable(a, b)
    zr_str_encoding_index(a) == zr_str_encoding_index(b) || RString.len(a) == 0 || RString.len(b) == 0 || (zr_str_ascii_only(a) && zr_str_ascii_only(b))
  end

  # Same as `zr_str_ascii_bytes_p`, under the name that the rest of the
  # kernel uses. The result is kept in `FL_ASCII`, so a String-keyed Hash
  # does not scan a key again on each lookup. `zr_str_modified` and an
  # encoding that cannot hold ASCII text clear `FL_ASCII`, so the kept
  # result is never stale.
  sig [Value] => Bool
  def zr_str_ascii_only(s)
    zr_str_ascii_bytes_p(s)
  end

  # `String#ascii_only?`, with the same kept result.
  sig [Value] => Value
  def zr_str_ascii_only_m(s)
    zr_bool(zr_str_ascii_bytes_p(s))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_STRING
      return Machine.value(QFALSE)
    end
    zr_bool(zr_bytes_eq(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other)) && zr_str_comparable(recv, other))
  end

  # `String#==`: compares another String by its bytes. For any other value
  # that responds to to_str, it calls `other == self`, as CRuby's
  # rb_str_equal does. `eql?` keeps the plain rule of zr_str_eq.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_equal(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if !zr_special_p(other) && zr_type(other) == T_STRING
      return zr_str_eq(recv, argc, argv, cref, blk)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_sym(Machine.id(:to_str))))
    responds = zr_send(other, Machine.id(:respond_to?), 1, slot)
    return responds if responds == QUNDEF
    if responds == QNIL || responds == QFALSE
      return Machine.value(QFALSE)
    end
    Machine.store64(slot, 0, Machine.word(recv))
    r = zr_send(other, Machine.id(:==), 1, slot)
    return r if r == QUNDEF
    zr_bool(r != QNIL && r != QFALSE)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_length(recv, argc, argv, cref, blk)
    zr_fix(zr_str_char_count(recv))
  end

  # Returns a frozen copy that keeps a subclass, as rb_str_new_frozen makes
  # one. A MatchData keeps this copy of the text it matched.
  sig [Value] => Value
  def zr_str_new_frozen_m(s)
    copy = zr_str_copy_encoding(zr_str_new(RString.ptr(s), RString.len(s)), s)
    RBasic.set_klass(copy, zr_real_class(s))
    RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE)
    copy
  end

  # Returns the character count, for core code that must not dispatch.
  sig [Value] => Value
  def zr_str_length_m(s)
    zr_fix(zr_str_char_count(s))
  end

  # Whether each byte is a character: a byte-oriented encoding, or text
  # with no non-ASCII byte.
  sig [Value] => Bool
  def zr_str_bytes_are_chars(s)
    if zr_str_unit(s) != 0
      return RString.len(s) == 0
    end
    if !zr_str_wide_p(s) && !zr_str_mb_p(s)
      return true
    end
    n = RString.len(s)
    i = 0
    while i < n
      if Machine.u8(Machine.load8(RString.ptr(s) + i, 0)) >= 128
        return false
      end
      i += 1
    end
    true
  end

  sig [Value] => Value
  def zr_str_ascii_check(s)
    zr_bool(zr_str_bytes_are_chars(s))
  end

  # Returns the byte length of the character at byte `off`: a whole UTF-8
  # sequence, a UTF-16 or UTF-32 character, else one byte.
  sig [Value, Word] => Word
  def zr_str_char_len_at(s, off)
    # Only the flag, never a scan, because this runs once for each character.
    if (RBasic.flags(s) & FL_ASCII) != 0
      return 1
    end
    if !zr_str_wide_p(s)
      unit = zr_str_unit(s)
      if unit != 0
        return zr_unit_char_len(s, off, unit)
      end
      if zr_str_mb_p(s)
        wide = zr_str_mb_len(s, off)
        return wide == 0 ? 1 : wide
      end
      return 1
    end
    len = zr_utf8_char_len(RString.ptr(s) + off, RString.len(s) - off)
    len == 0 ? 1 : len
  end

  sig [Value] => Word
  def zr_str_char_count(s)
    n = RString.len(s)
    # A scan that found the bytes ASCII gives the result first, with one
    # flag check.
    if (RBasic.flags(s) & FL_ASCII) != 0 || (!zr_str_wide_p(s) && zr_str_unit(s) == 0 && !zr_str_mb_p(s)) || zr_str_ascii_bytes_p(s)
      return n
    end
    # Valid UTF-8 is counted eight bytes at a time. One scan decides that it
    # is valid, and the flag then keeps that result.
    if zr_str_encoding_index(s) == ENC_UTF8 && zr_str_valid_p(s) == QTRUE
      return zr_utf8_char_count(RString.ptr(s), n)
    end
    count = 0
    i = 0
    while i < n
      i += zr_str_char_len_at(s, i)
      count += 1
    end
    count
  end

  # Returns the byte offset of character `index` in `n` bytes of valid
  # UTF-8, or -1 past the end: the place of the next byte that starts a
  # character once `index` of them are behind. It passes eight bytes at a
  # time while they hold no more starts than it still needs, as
  # `zr_utf8_char_count` counts them.
  sig [Ptr, Word, Word] => Word
  def zr_utf8_char_offset(p, n, index)
    need = index
    i = 0
    while i + 8 <= n
      w = Machine.load64(p + i, 0)
      starts = 8 - Machine.popcnt((w >> 7) & ((w >> 6) ^ (0 - 1)) & 0x0101010101010101)
      if starts > need
        break
      end
      need -= starts
      i += 8
    end
    while i < n
      if (Machine.u8(Machine.load8(p + i, 0)) & 0xC0) != 0x80
        if need == 0
          return i
        end
        need -= 1
      end
      i += 1
    end
    need == 0 ? n : 0 - 1
  end

  # Returns the number of characters in `n` bytes of valid UTF-8: all bytes
  # except the continuation bytes, which are `10xxxxxx`. It counts eight
  # bytes at a time (`popcnt` of one bit for each byte), then one at a time.
  sig [Ptr, Word] => Word
  def zr_utf8_char_count(p, n)
    count = n
    i = 0
    while i + 8 <= n
      w = Machine.load64(p + i, 0)
      count -= Machine.popcnt((w >> 7) & ((w >> 6) ^ (0 - 1)) & 0x0101010101010101)
      i += 8
    end
    while i < n
      if (Machine.u8(Machine.load8(p + i, 0)) & 0xC0) == 0x80
        count -= 1
      end
      i += 1
    end
    count
  end

  # Returns the byte offset of character `index` (a negative index counts
  # from the end). The character count maps to the end. Past that, -1.
  sig [Value, Word] => Word
  def zr_str_char_offset(s, index)
    n = RString.len(s)
    # One byte for each character: the index is the offset.
    if (RBasic.flags(s) & FL_ASCII) != 0 || (!zr_str_wide_p(s) && zr_str_unit(s) == 0 && !zr_str_mb_p(s)) || zr_str_ascii_bytes_p(s)
      if index < 0
        index += n
      end
      if index < 0 || index > n
        return 0 - 1
      end
      return index
    end
    if index < 0
      index += zr_str_char_count(s)
      if index < 0
        return 0 - 1
      end
    end
    if zr_str_encoding_index(s) == ENC_UTF8 && zr_str_valid_p(s) == QTRUE
      return zr_utf8_char_offset(RString.ptr(s), n, index)
    end
    i = 0
    while index > 0
      if i >= n
        return 0 - 1
      end
      i += zr_str_char_len_at(s, i)
      index -= 1
    end
    i
  end

  sig [Value, Value] => Value
  def zr_str_char_offset_m(s, index)
    off = zr_str_char_offset(s, zr_fix2long(index))
    off < 0 ? Machine.value(QNIL) : zr_fix(off)
  end

  # Returns the character index of byte `off`.
  sig [Value, Value] => Value
  def zr_str_byte_to_char(s, off)
    stop = zr_fix2long(off)
    # One byte for each character: the offset is the index.
    if (RBasic.flags(s) & FL_ASCII) != 0 || (!zr_str_wide_p(s) && zr_str_unit(s) == 0 && !zr_str_mb_p(s)) || zr_str_ascii_bytes_p(s)
      return off
    end
    if zr_str_encoding_index(s) == ENC_UTF8 && zr_str_valid_p(s) == QTRUE && stop <= RString.len(s)
      return zr_fix(zr_utf8_char_count(RString.ptr(s), stop))
    end
    i = 0
    count = 0
    while i < stop
      i += zr_str_char_len_at(s, i)
      count += 1
    end
    zr_fix(count)
  end

  # Returns `len` characters from character `start`, or nil past the end.
  sig [Value, Value, Value] => Value
  def zr_str_char_slice(s, start, len)
    count = zr_fix2long(len)
    if count < 0
      return Machine.value(QNIL)
    end
    from = zr_str_char_offset(s, zr_fix2long(start))
    if from < 0
      return Machine.value(QNIL)
    end
    to = from
    n = RString.len(s)
    while count > 0 && to < n
      to += zr_str_char_len_at(s, to)
      count -= 1
    end
    zr_str_copy_encoding(zr_str_new(RString.ptr(s) + from, to - from), s)
  end

  sig [Value, Value] => Value
  def zr_str_char_len_at_m(s, off)
    zr_fix(zr_str_char_len_at(s, zr_fix2long(off)))
  end

  # Returns the code point that CESU-8 encodes in the `width` bytes at `p`:
  # two or three bytes as in UTF-8, or six bytes that contain a surrogate
  # pair.
  sig [Ptr, Word] => Word
  def zr_cesu8_point(p, width)
    if width == 2
      return ((Machine.u8(Machine.load8(p, 0)) & 31) << 6) | (Machine.u8(Machine.load8(p + 1, 0)) & 63)
    end
    high = ((Machine.u8(Machine.load8(p, 0)) & 15) << 12) | ((Machine.u8(Machine.load8(p + 1, 0)) & 63) << 6) | (Machine.u8(Machine.load8(p + 2, 0)) & 63)
    if width < 6
      return high
    end
    low = ((Machine.u8(Machine.load8(p + 4, 0)) & 63) << 6) | (Machine.u8(Machine.load8(p + 5, 0)) & 63)
    65536 + ((high - 55296) << 10) + (low & 1023)
  end

  # Returns the code point of the first character.
  sig [Value] => Value
  def zr_str_ord(s)
    if RString.len(s) == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty string"), 12)
    end
    zr_str_ord_at(s, 0)
  end

  # Returns the code point of the character that starts at byte `off`. A
  # loop over the characters reads it without a String for each character.
  sig [Value, Value] => Value
  def zr_str_ord_at_m(s, off)
    zr_str_ord_at(s, zr_fix2long(off))
  end

  sig [Value, Word] => Value
  def zr_str_ord_at(s, off)
    n = RString.len(s) - off
    unit = zr_str_unit(s)
    if unit != 0
      width = zr_unit_char_len(s, off, unit)
      if !zr_unit_char_valid_p(s, off, width, unit)
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("invalid byte sequence in "), 25)
        zr_buf_unit_name(b, zr_str_encoding_index(s))
        return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
      end
      return zr_fix(zr_unit_point(s, off, width, unit))
    end
    p = RString.ptr(s) + off
    c = Machine.u8(Machine.load8(p, 0))
    # In a multibyte encoding, the number of a character is the number that
    # its bytes give, as rb_enc_codepoint does: EUC-JP's A4 A2 is 42146.
    if c >= 128 && zr_str_mb_p(s)
      width = zr_str_mb_len(s, off)
      if width == 0
        return zr_str_bad_bytes(s)
      end
      if zr_str_encoding_index(s) == ENC_CESU8
        return zr_fix(zr_cesu8_point(p, width))
      end
      v = 0
      k = 0
      while k < width
        v = (v << 8) | Machine.u8(Machine.load8(p + k, 0))
        k += 1
      end
      return zr_fix(v)
    end
    if c < 128 || !zr_str_wide_p(s)
      return zr_fix(c)
    end
    len = zr_utf8_char_len(p, n)
    if len == 0
      return zr_str_bad_bytes(s)
    end
    cp = c & ((1 << (7 - len)) - 1)
    i = 1
    while i < len
      cp = (cp << 6) | (Machine.u8(Machine.load8(p + i, 0)) & 63)
      i += 1
    end
    zr_fix(cp)
  end

  # US-ASCII stops at 128, UTF-8 needs whole sequences, and every other
  # encoding of this runtime accepts any byte.
  sig [Value] => Value
  def zr_str_valid_p(s)
    # Plain ASCII is valid in each encoding that can hold it, and the
    # ASCII scan's result also carries over to slices (zr_str_piece).
    if (RBasic.flags(s) & FL_VALID) != 0 || zr_str_ascii_bytes_p(s)
      RBasic.set_flags(s, RBasic.flags(s) | FL_VALID)
      return Machine.value(QTRUE)
    end
    valid = zr_str_valid_scan(s)
    if valid == QTRUE
      RBasic.set_flags(s, RBasic.flags(s) | FL_VALID)
    end
    valid
  end

  sig [Value] => Value
  def zr_str_valid_scan(s)
    if zr_str_encoding_index(s) == ENC_USASCII
      return zr_bool(zr_str_ascii_bytes_p(s))
    end
    unit = zr_str_unit(s)
    if unit != 0
      at = 0
      while at < RString.len(s)
        width = zr_unit_char_len(s, at, unit)
        if !zr_unit_char_valid_p(s, at, width, unit)
          return Machine.value(QFALSE)
        end
        at += width
      end
      return Machine.value(QTRUE)
    end
    if zr_str_mb_p(s)
      stop = RString.len(s)
      at = 0
      while at < stop
        width = zr_str_mb_len(s, at)
        if width == 0
          return Machine.value(QFALSE)
        end
        at += width
      end
      return Machine.value(QTRUE)
    end
    if !zr_str_wide_p(s)
      return Machine.value(QTRUE)
    end
    n = RString.len(s)
    i = 0
    while i < n
      # A run of ASCII, eight bytes at a time, is valid as it is.
      while i + 8 <= n && (Machine.load64(RString.ptr(s) + i, 0) & Machine.word(0x8080808080808080)) == 0
        i += 8
      end
      if i < n
        if Machine.u8(Machine.load8(RString.ptr(s) + i, 0)) >= 128 && zr_utf8_char_len(RString.ptr(s) + i, n - i) == 0
          return Machine.value(QFALSE)
        end
        i += zr_str_char_len_at(s, i)
      end
    end
    Machine.value(QTRUE)
  end

  # Returns the error for a String whose bytes are not all characters, or
  # nil when they are.
  sig [Value, Ptr, Word] => Value
  def zr_non_ascii_stop(s, what, len)
    if zr_str_bytes_are_chars(s)
      return Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("String#"), 7)
    zr_buf_push(b, what, len)
    zr_buf_push(b, Machine.bytes(" on a non-ASCII String"), 22)
    zr_unimplemented(zr_buf_take(b))
  end

  # Returns a copy with each byte mapped: 1 upcases, 2 downcases, 3
  # capitalizes.
  sig [Value, Word] => Value
  def zr_str_map_case(s, how)
    r = zr_non_ascii_stop(s, Machine.bytes("upcase, downcase or capitalize"), 30)
    return r if r == QUNDEF
    n = RString.len(s)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    i = 0
    while i < n
      c = Machine.u8(Machine.load8(RString.ptr(s) + i, 0))
      up = how == 1 || (how == 3 && i == 0)
      if up && c >= 97 && c <= 122
        c -= 32
      elsif !up && c >= 65 && c <= 90
        c += 32
      end
      zr_buf_byte(b, c)
      i += 1
    end
    zr_str_copy_encoding(zr_buf_take(b), s)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_upcase(recv, argc, argv, cref, blk)
    zr_str_map_case(recv, 1)
  end

  # The core's own case mapping, which skips any String method that a
  # program adds.
  sig [Value, Value] => Value
  def zr_str_map_case_m(s, how)
    zr_str_map_case(s, zr_fix2long(how))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_downcase(recv, argc, argv, cref, blk)
    zr_str_map_case(recv, 2)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_capitalize(recv, argc, argv, cref, blk)
    zr_str_map_case(recv, 3)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_reverse(recv, argc, argv, cref, blk)
    # The code finds the characters from the front, where they start, and
    # puts each one in its place from the back. An invalid byte is one
    # character.
    n = RString.len(recv)
    out = zr_str_new(RString.ptr(recv), n)
    i = 0
    while i < n
      len = zr_str_char_len_at(recv, i)
      zr_memmove(RString.ptr(out) + n - i - len, RString.ptr(recv) + i, len)
      i += len
    end
    zr_str_copy_encoding(out, recv)
  end

  # Returns the byte index of `needle` in `hay` from `from`, or -1. A
  # needle that is not valid in its encoding never matches, as
  # rb_str_index decides.
  sig [Value, Value, Word] => Word
  def zr_str_find(hay, needle, from)
    if zr_str_valid_p(needle) == QFALSE
      return 0 - 1
    end
    zr_bytes_find(RString.ptr(hay), RString.len(hay), RString.ptr(needle), RString.len(needle), from)
  end

  Libc.import :memmem, [Ptr, Word, Ptr, Word] => Ptr

  # Returns the offset of the `m` bytes at `needle` in the `n` bytes at
  # `hay`, at or after byte `from`, or -1. An empty needle is found at
  # `from`, which some libc memmem implementations do not return when the
  # rest is empty.
  sig [Ptr, Word, Ptr, Word, Word] => Word
  def zr_bytes_find(hay, n, needle, m, from)
    if from + m > n
      return 0 - 1
    end
    if m == 0
      return from
    end
    p = Libc.memmem(hay + from, n - from, needle, m)
    if p == 0
      return 0 - 1
    end
    p - hay
  end

  # `s.split(sep)` by the bytes of a String: the piece before each match
  # and, after the last, the rest (kept under a limit, or when it is not
  # empty). A `limit` above 0 sets the maximum number of pieces. The core
  # checks the encodings and the bytes first, and drops trailing empty
  # pieces for a limit of 0.
  sig [Value, Value, Value] => Value
  def zr_str_split_by(s, sep, limit_v)
    limit = zr_fix2long(limit_v)
    n = RString.len(s)
    m = RString.len(sep)
    out = zr_ary_new(8)
    beg = 0
    pieces = 1
    while limit <= 0 || pieces < limit
      i = zr_bytes_find(RString.ptr(s), n, RString.ptr(sep), m, beg)
      if i < 0
        break
      end
      zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, i - beg), s))
      beg = i + m
      pieces += 1
    end
    if n > 0 && (limit != 0 || n > beg)
      zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, n - beg), s))
    end
    # With no limit, the empty pieces at the end are dropped.
    if limit == 0
      while RArray.len(out) > 0 && RString.len(zr_ary_at(out, RArray.len(out) - 1)) == 0
        RArray.set_len(out, RArray.len(out) - 1)
      end
    end
    out
  end

  # `split` with no pattern or " ": the pieces between runs of blanks. It
  # skips the leading blanks and, under a limit, keeps the text after the
  # last piece, as split_words does.
  sig [Value, Value] => Value
  def zr_str_split_words(s, limit_v)
    limit = zr_fix2long(limit_v)
    n = RString.len(s)
    out = zr_ary_new(8)
    beg = 0
    while beg < n && zr_blank_byte_p(Machine.u8(Machine.load8(RString.ptr(s) + beg, 0)))
      beg += 1
    end
    while beg < n
      if limit > 0 && limit <= RArray.len(out) + 1
        break
      end
      stop = beg
      while stop + 8 <= n && !zr_blank_word_p(Machine.load64(RString.ptr(s) + stop, 0))
        stop += 8
      end
      while stop < n && !zr_blank_byte_p(Machine.u8(Machine.load8(RString.ptr(s) + stop, 0)))
        stop += 1
      end
      if stop == n
        break
      end
      zr_ary_push(out, zr_str_piece(s, RString.ptr(s) + beg, stop - beg))
      beg = stop
      while beg < n && zr_blank_byte_p(Machine.u8(Machine.load8(RString.ptr(s) + beg, 0)))
        beg += 1
      end
    end
    if n > 0 && (limit != 0 || n > beg)
      zr_ary_push(out, zr_str_piece(s, RString.ptr(s) + beg, n - beg))
    end
    out
  end

  # Whether `sep` is the one String that splits on blanks: " ".
  sig [Value] => Value
  def zr_str_blank_sep_p(sep)
    if zr_special_p(sep) || zr_type(sep) != T_STRING
      return Machine.value(QFALSE)
    end
    zr_bool(RString.len(sep) == 1 && Machine.u8(Machine.load8(RString.ptr(sep), 0)) == 32)
  end

  # Whether `sep` is a String that splits by its bytes: not empty (which
  # splits into characters), and not " " (which splits on blanks).
  sig [Value] => Value
  def zr_str_plain_sep_p(sep)
    if zr_special_p(sep) || zr_type(sep) != T_STRING
      return Machine.value(QFALSE)
    end
    n = RString.len(sep)
    zr_bool(n > 1 || (n == 1 && Machine.u8(Machine.load8(RString.ptr(sep), 0)) != 32))
  end

  # `s.to_i` in base 10 when the result is a fixnum. It reads leading
  # blanks (C's isspace, so not NUL, which the core's strip removes), a
  # sign, and digits with single underscores between them, and stops at the
  # first other byte. It returns nil and leaves the rest to the core for a
  # `0d` prefix, or a number of more than 18 digits.
  sig [Value] => Value
  def zr_str_to_i10(s)
    p = RString.ptr(s)
    n = RString.len(s)
    i = 0
    while i < n && zr_blank_byte_p(Machine.u8(Machine.load8(p + i, 0)))
      i += 1
    end
    negative = false
    if i < n
      b = Machine.u8(Machine.load8(p + i, 0))
      if b == 45 || b == 43
        negative = b == 45
        i += 1
      end
    end
    v = 0
    digits = 0
    start = i
    while i < n
      b = Machine.u8(Machine.load8(p + i, 0))
      if zr_digit_byte_p(b)
        # A 19th digit can overflow the word, so stop before it.
        if digits == 18
          return Machine.value(QNIL)
        end
        v = (v * 10) + (b - 48)
        digits += 1
        i += 1
      elsif b == 95 && digits > 0 && i + 1 < n && zr_digit_byte_p(Machine.u8(Machine.load8(p + i + 1, 0)))
        i += 1
      else
        break
      end
    end
    # `0d12`: a prefix that the core reads, not a zero.
    if digits == 1 && i == start + 1 && v == 0 && i < n
      b = Machine.u8(Machine.load8(p + i, 0))
      if b == 100 || b == 68
        return Machine.value(QNIL)
      end
    end
    zr_fix(negative ? 0 - v : v)
  end

  sig [Word] => Bool
  def zr_blank_byte_p(b)
    b == 32 || (b >= 9 && b <= 13)
  end

  sig [Word] => Bool
  def zr_digit_byte_p(b)
    b >= 48 && b <= 57
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_include_p(recv, argc, argv, cref, blk)
    other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
    return other if other == QUNDEF
    zr_bool(zr_str_find(recv, other, 0) >= 0)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_index(recv, argc, argv, cref, blk)
    other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
    return other if other == QUNDEF
    i = zr_str_find(recv, other, 0)
    if i < 0
      return Machine.value(QNIL)
    end
    zr_str_byte_to_char(recv, zr_fix(i))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_empty_p(recv, argc, argv, cref, blk)
    zr_bool(RString.len(recv) == 0)
  end

  # `to_sym`: a Symbol is its bytes and their encoding, the key that
  # rb_str_intern uses. ASCII bytes give the same Symbol in every encoding.
  # Bytes that are invalid in their encoding give no Symbol.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_to_sym(recv, argc, argv, cref, blk)
    if zr_str_ascii_bytes_p(recv)
      return zr_sym(zr_intern(RString.ptr(recv), RString.len(recv)))
    end
    if zr_str_valid_p(recv) == QFALSE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("invalid symbol in encoding "), 27)
      if zr_str_wide_p(recv)
        zr_buf_push(b, Machine.bytes("UTF-8"), 5)
      else
        zr_buf_push(b, Machine.bytes("US-ASCII"), 8)
      end
      zr_buf_push(b, Machine.bytes(" :"), 2)
      s = zr_inspect(recv)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      return zr_raise_buf(zr_core_class(Machine.id(:EncodingError)), b)
    end
    tag = (RBasic.flags(recv) >> FL_ENC_SHIFT) & 255
    zr_sym(zr_intern_tagged(RString.ptr(recv), RString.len(recv), tag))
  end

  # `+str`: returns the string itself unless it is frozen or chilled.
  # Otherwise it returns a copy that is not, with its encoding and class,
  # as rb_str_dup makes it.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_uplus(recv, argc, argv, cref, blk)
    if zr_frozen_p(recv) || zr_str_chilled_p(recv)
      copy = zr_str_copy_encoding(zr_str_new(RString.ptr(recv), RString.len(recv)), recv)
      RBasic.set_klass(copy, zr_real_class(recv))
      return copy
    end
    recv
  end

  # `-str`, as CRuby's str_uminus decides. A bare String (class String, no
  # ivars) is interned: itself when it is frozen, else a copy of its bytes
  # and encoding. Any other String is not interned: a frozen one returns
  # itself, and an unfrozen one returns a frozen copy of its class.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_str_uminus(recv, argc, argv, cref, blk)
    bare = RBasic.klass(recv) == zr_global(G_STRING) && (RBasic.flags(recv) & FL_EXIVAR) == 0
    if zr_frozen_p(recv)
      return bare ? zr_str_intern(recv) : recv
    end
    copy = zr_str_copy_encoding(zr_str_new(RString.ptr(recv), RString.len(recv)), recv)
    if zr_real_class(recv) != zr_global(G_STRING)
      RBasic.set_klass(copy, zr_real_class(recv))
      RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE)
      return copy
    end
    zr_str_intern(copy)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_freeze(recv, argc, argv, cref, blk)
    unless zr_special_p(recv)
      RBasic.set_flags(recv, (RBasic.flags(recv) | FL_FREEZE) & (zr_type(recv) == T_STRING ? FL_CHILLED_CLEAR : 0 - 1))
      # The singleton class freezes with its object, as CRuby's
      # rb_freeze_singleton_class does.
      k = RBasic.klass(recv)
      if zr_singleton_p(k) && RClass.attached(k) == recv
        RBasic.set_flags(k, RBasic.flags(k) | FL_FREEZE)
      end
    end
    recv
  end

  # Freezes an Array or Hash literal that a
  # `# shareable_constant_value: literal` constant contains, while it is
  # built. It sets only the flag and sends nothing, as compile.c freezes
  # the object that it made at compile time.
  sig [Value] => Value
  def zr_literal_freeze(v)
    RBasic.set_flags(v, RBasic.flags(v) | FL_FREEZE)
    v
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_frozen_p(recv, argc, argv, cref, blk)
    zr_bool(zr_frozen_p(recv))
  end

  # `succ` of an ASCII string: the rightmost alphanumeric run counts up
  # with carries, as in CRuby. A string with no alphanumerics increments
  # its last byte. The core does other strings.
  sig [Value] => Value
  def zr_str_succ_ascii(recv)
    n = RString.len(recv)
    if n == 0
      return zr_str_new(Machine.bytes(""), 0)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, RString.ptr(recv), n)
    p = Buf.ptr(b)
    i = n - 1
    alnum = false
    while i >= 0
      c = Machine.u8(Machine.load8(p + i, 0))
      if zr_alnum_p(c)
        alnum = true
        break_here = false
        if c == 122
          Machine.store8(p + i, 0, Machine.i8(97))
        elsif c == 90
          Machine.store8(p + i, 0, Machine.i8(65))
        elsif c == 57
          Machine.store8(p + i, 0, Machine.i8(48))
        else
          Machine.store8(p + i, 0, Machine.i8(c + 1))
          break_here = true
        end
        if break_here
          return zr_buf_take(b)
        end
        # A carry past the leftmost alphanumeric inserts a new one. So does a
        # carry that would cross a gap into the other kind (a letter after a
        # digit, or a digit after a letter).
        j = i - 1
        while j >= 0 && !zr_alnum_p(Machine.u8(Machine.load8(p + j, 0)))
          j -= 1
        end
        if j >= 0 && j < i - 1 && (c <= 57) != (Machine.u8(Machine.load8(p + j, 0)) <= 57)
          j = 0 - 1
        end
        if j < 0
          first = c == 122 ? 97 : (c == 90 ? 65 : 49)
          zr_buf_byte(b, 0)
          p = Buf.ptr(b)
          k = Buf.len(b) - 1
          while k > i
            Machine.store8(p + k, 0, Machine.load8(p + k - 1, 0))
            k -= 1
          end
          Machine.store8(p + i, 0, Machine.i8(first))
          return zr_buf_take(b)
        end
        i = j
      else
        if alnum
          i -= 1
        else
          i -= 1
        end
      end
    end
    unless alnum
      Machine.store8(p + n - 1, 0, Machine.i8(Machine.u8(Machine.load8(p + n - 1, 0)) + 1))
    end
    zr_buf_take(b)
  end

  sig [Word] => Bool
  def zr_alnum_p(c)
    (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
  end

  # `"a#{b}c"`: joins the `to_s` of each piece. A `to_s` that returns no
  # String falls back to the plain object form, as in CRuby. The result
  # starts in the encoding of the first piece, and each piece joins it as
  # rb_str_buf_append joins one: a non-ASCII piece changes a plain ASCII
  # result to its own encoding, and two non-ASCII pieces in two encodings
  # are an error. A result in US-ASCII takes the encoding of any piece that
  # is not US-ASCII (rb_str_concat_literals).
  sig [Word, Ptr] => Value
  def zr_str_interp(argc, argv)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    index = ENC_UTF8
    i = 0
    while i < argc
      v = Machine.value(Machine.load64(argv + (i * 8), 0))
      s = v
      if zr_special_p(v) || zr_type(v) != T_STRING
        s = zr_obj_as_string(v)
        if s == QUNDEF
          zr_buf_free(b)
          return s
        end
      end
      if zr_special_p(s) || zr_type(s) != T_STRING
        s = zr_str_from_buf_obj_head(v)
      end
      piece = zr_str_encoding_index(s)
      joined = piece
      if i > 0
        joined = index
        # Whether the pieces so far are plain ASCII matters only for a
        # piece in another encoding: the buffer's bytes say it then.
        if piece != index && RString.len(s) != 0
          joined = zr_enc_append_str(index, zr_bytes_ascii_only_p(Buf.ptr(b), Buf.len(b)), Buf.len(b), s)
        end
      end
      if joined == ENC_NONE
        return zr_str_join_incompatible(zr_str_set_index(zr_buf_take(b), index), s)
      end
      index = piece != ENC_USASCII && joined == ENC_USASCII ? piece : joined
      zr_buf_str(b, s)
      i += 1
    end
    zr_str_set_index(zr_buf_take(b), index)
  end

  # Returns the plain object form, `#<Class:0x...>`, as a String.
  sig [Value] => Value
  def zr_str_from_buf_obj_head(v)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, v)
    zr_buf_byte(b, 62)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # A frozen literal: the same String object at every evaluation.
  sig [Ptr, Word] => Value
  def zr_str_frozen(bytes, len)
    zr_str_intern(zr_str_new(bytes, len))
  end

  # A String that a literal made in a file with no frozen_string_literal
  # setting (STR_CHILLED_LITERAL), or that `Symbol#to_s` made
  # (STR_CHILLED_SYMBOL_TO_S). It is not frozen, but its first change warns
  # that it will be frozen, and after that it is an ordinary String.
  FL_CHILLED = 1 << 15
  FL_CHILLED_SYMBOL = 1 << 16
  FL_CHILLED_CLEAR = 0 - FL_CHILLED - FL_CHILLED_SYMBOL - 1

  sig [Ptr, Word] => Value
  def zr_str_new_chilled(bytes, len)
    s = zr_str_new(bytes, len)
    RBasic.set_flags(s, RBasic.flags(s) | FL_CHILLED)
    s
  end

  sig [Ptr, Word, Word] => Value
  def zr_str_new_chilled_at(bytes, len, index)
    s = zr_str_new_at(bytes, len, index)
    RBasic.set_flags(s, RBasic.flags(s) | FL_CHILLED)
    s
  end

  sig [Value] => Bool
  def zr_str_chilled_p(s)
    !zr_special_p(s) && zr_type(s) == T_STRING && (RBasic.flags(s) & (FL_CHILLED | FL_CHILLED_SYMBOL)) != 0
  end

  # Whether a change to `v` is refused because `v` is frozen, as
  # rb_check_frozen checks. A chilled String changes, and warns first when
  # deprecation warnings are on, as CHILLED_STRING_MUTATED does.
  sig [Value] => Bool
  def zr_modify_frozen_p(v)
    if zr_special_p(v)
      true
    elsif (RBasic.flags(v) & T_MASK) == T_STRING && (RBasic.flags(v) & (FL_CHILLED | FL_CHILLED_SYMBOL | FL_SNAPSHOT)) != 0
      zr_str_modify_marked_p(v)
    else
      (RBasic.flags(v) & FL_FREEZE) != 0
    end
  end
  # Each write to a String checks this first, so the test of the flags is
  # in the writer's code; a chilled or snapshot String is a call.
  inline :zr_modify_frozen_p

  sig [Value] => Bool
  def zr_str_modify_marked_p(v)
    flags = RBasic.flags(v)
    if (flags & (FL_CHILLED | FL_CHILLED_SYMBOL)) != 0
      zr_str_unchill(v)
      flags = RBasic.flags(v)
    end
    if (flags & FL_SNAPSHOT) != 0
      RBasic.set_flags(v, flags & FL_SNAPSHOT_CLEAR)
    end
    (flags & FL_FREEZE) != 0
  end

  sig [Value] => Value
  def zr_modify_frozen_m(v)
    zr_bool(zr_modify_frozen_p(v))
  end

  # `Warning[:deprecated]`, as the core last set it.
  sig [Value] => Value
  def zr_warn_deprecated_set(flag)
    Machine.store64(Machine.static(:warn_deprecated, 8), 0, flag == QNIL || flag == QFALSE ? 0 : 1)
    flag
  end

  sig [Value] => Void
  def zr_str_unchill(s)
    symbol = (RBasic.flags(s) & FL_CHILLED_SYMBOL) != 0
    RBasic.set_flags(s, RBasic.flags(s) & FL_CHILLED_CLEAR)
    if Machine.load64(Machine.static(:warn_deprecated, 8), 0) == 0 || zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if symbol
      zr_buf_push(b, Machine.bytes("string returned by :"), 20)
      zr_buf_push(b, RString.ptr(s), RString.len(s))
      zr_buf_push(b, Machine.bytes(".to_s will be frozen in the future"), 34)
    else
      zr_buf_push(b, Machine.bytes("literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)"), 105)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_buf_take(b)))
    r = zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:deprecated), 1, slot)
    # The check that called this returns true or false, so a warning that
    # raises is dropped here.
    if r == QUNDEF
      Task.set_pending(zr_task(), Machine.value(QNIL))
    end
  end

  # The same three, for a file whose script encoding is not UTF-8: the
  # literal gets the encoding before any code reads its bytes.
  sig [Ptr, Word, Word] => Value
  def zr_str_new_at(bytes, len, index)
    zr_str_set_index(zr_str_new(bytes, len), index)
  end

  sig [Ptr, Word, Word] => Value
  def zr_str_frozen_at(bytes, len, index)
    zr_str_intern(zr_str_new_at(bytes, len, index))
  end

  sig [Ptr, Word, Word] => Value
  def zr_str_literal_freeze_at(bytes, len, index)
    if (Machine.gates & GATE_FREEZE) != 0
      return zr_send(zr_str_new_at(bytes, len, index), Machine.id(:freeze), 0, 0)
    end
    zr_str_frozen_at(bytes, len, index)
  end

  # `"lit".freeze`: the shared frozen String, unless the program redefined
  # String#freeze, which then runs as any send does.
  sig [Ptr, Word] => Value
  def zr_str_literal_freeze(bytes, len)
    if (Machine.gates & GATE_FREEZE) != 0
      return zr_send(zr_str_new(bytes, len), Machine.id(:freeze), 0, 0)
    end
    zr_str_literal_shared(bytes, len)
  end

  G_FROZEN_LITERALS = 52

  # The one frozen String of a UTF-8 literal, kept under the address of
  # its bytes.
  #
  # `zr_str_frozen` also returns the same object at every evaluation (that
  # is the purpose of the fstring table), but to find it, it makes a
  # String, copies the bytes, hashes them and discards the new String.
  # Under `frozen_string_literal: true` that is an allocation, a malloc, a
  # copy and a hash of every byte each time a literal runs, which in a
  # compiler is most of the work.
  #
  # The key is the address of the bytes, which the emitter already passes,
  # so a hit costs one hash of one word. The table is a rooted Hash, so the
  # collector marks the String in it.
  #
  # An address alone does not identify a literal: eval support maps code
  # at run time, and a freed mapping gives its addresses back. So on a hit,
  # the code compares the bytes that it found with the requested bytes. It
  # keeps the entry only when they are equal, and otherwise replaces it.
  # The check is a compare, not an allocation, and it makes a recycled
  # address return the literal that is there now.
  sig [Ptr, Word] => Value
  def zr_str_literal_shared(bytes, len)
    table = zr_global(G_FROZEN_LITERALS)
    if zr_special_p(table)
      table = zr_hash_new()
      zr_set_global(G_FROZEN_LITERALS, table)
    end
    key = zr_fix(Machine.word(bytes))
    found = zr_hash_lookup(table, key)
    if found != QUNDEF && zr_bytes_eq(bytes, len, RString.ptr(found), RString.len(found))
      return found
    end
    s = zr_str_frozen(bytes, len)
    zr_hash_store(table, key, s)
    s
  end

  # The same, kept in `cell`, the word of the literal site, which the site
  # reads after that with no call. The table above keeps it rooted.
  sig [Ptr, Ptr, Word] => Value
  def zr_str_literal_cell(cell, bytes, len)
    s = zr_str_literal_shared(bytes, len)
    Machine.store64(cell, 0, Machine.word(s))
    s
  end

  GATE_FREEZE = 32768

  G_FSTRINGS = 44

  # CRuby's fstring table: returns the one frozen String of these bytes. A
  # String not yet in the table is frozen and added. A String that is not
  # UTF-8 is frozen but not shared, because the table uses only bytes as keys.
  sig [Value] => Value
  def zr_str_intern(s)
    if !zr_str_wide_p(s)
      RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE)
      return s
    end
    table = zr_global(G_FSTRINGS)
    if zr_special_p(table)
      table = zr_hash_new()
      zr_set_global(G_FSTRINGS, table)
    end
    found = zr_hash_lookup(table, s)
    if found != QUNDEF
      return found
    end
    RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE | FL_FSTR)
    zr_hash_store(table, s, s)
    s
  end

  # A String in the fstring table, which cannot have a singleton class
  # (CRuby's RSTRING_FSTR).
  FL_FSTR = 1 << 22

  GATE_LTLT = 16384

  # `recv << v` as CRuby's opt_ltlt runs it: a String or Array whose `<<`
  # is its own appends directly, with no frame.
  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_ltlt(recv, mid, argc, argv, mode)
    if !zr_special_p(recv) && (Machine.gates & GATE_LTLT) == 0
      k = RBasic.klass(recv)
      other = Machine.value(Machine.load64(argv, 0))
      if k == zr_global(G_STRING) && !zr_special_p(other) && RBasic.klass(other) == zr_global(G_STRING)
        return zr_str_concat(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
      # An ASCII codepoint to append: only a frozen receiver can raise, and
      # that does not need the frame of the builtin.
      if k == zr_global(G_STRING) && zr_fixnum_p(other) && Machine.word(other) < 257 && Machine.word(other) > 0
        return zr_str_concat(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
      # `<<` takes one argument, so push it here unless a frozen Array
      # must raise.
      if k == zr_global(G_ARRAY) && argc == 1 && !zr_modify_frozen_p(recv)
        zr_ary_push(recv, other)
        return recv
      end
      if k == zr_global(G_ARRAY)
        return zr_ary_push_m(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
      end
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  # `recv.getbyte(i)` and `recv.setbyte(i, b)` on a String whose method is
  # its own, with fixnum arguments: calls the primitive directly, with no
  # frame. Without this, `bm_ruby_xor` spent two fifths of its time in the
  # builtin calls. Any other receiver or argument dispatches.
  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_getbyte(recv, mid, argc, argv, mode)
    if argc == 1 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_STRING) && (Machine.gates & GATE_GETBYTE) == 0
      i = Machine.value(Machine.load64(argv, 0))
      if zr_fixnum_p(i)
        return zr_str_byte_at(recv, i)
      end
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  sig [Value, Word, Word, Ptr, Word] => Value
  def zr_opt_setbyte(recv, mid, argc, argv, mode)
    if argc == 2 && !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_STRING) && (Machine.gates & GATE_SETBYTE) == 0
      i = Machine.value(Machine.load64(argv, 0))
      b = Machine.value(Machine.load64(argv, 8))
      if zr_fixnum_p(i) && zr_fixnum_p(b)
        return zr_str_setbyte(recv, i, b)
      end
    end
    zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
  end

  # The primitives that lib/zr/runtime/core/string.rb builds its methods on.

  sig [Value] => Value
  def zr_str_bytesize(s)
    zr_fix(RString.len(s))
  end

  # Returns the byte at `i`, or nil past the end.
  sig [Value, Value] => Value
  def zr_str_byte_at(s, i)
    # An index that is not a fixnum is past the end of every String.
    if !zr_fixnum_p(i)
      return Machine.value(QNIL)
    end
    n = zr_fix2long(i)
    if n < 0
      n += RString.len(s)
    end
    if n < 0 || n >= RString.len(s)
      return Machine.value(QNIL)
    end
    zr_fix(Machine.u8(Machine.load8(RString.ptr(s) + n, 0)))
  end

  # Whether the bytes of `other` are the bytes of the receiver from byte
  # `at`. This is the comparison that rb_str_start_with and rb_str_end_with
  # make after the two encodings join and the offset is on a character
  # boundary. The code reads the bytes where they are, and does not copy
  # the front or tail of the receiver into a new String only to compare
  # and discard it. That copy costs a cell, a malloc and a copy for each
  # call, and `start_with?` is the most frequently called method of the
  # compiler.
  sig [Value, Value, Value] => Value
  def zr_str_bytes_at_m(s, at, other)
    off = zr_fix2long(at)
    n = RString.len(other)
    if off < 0 || off + n > RString.len(s)
      return Machine.value(QFALSE)
    end
    zr_bool(zr_bytes_eq(RString.ptr(s) + off, n, RString.ptr(other), n))
  end

  # Returns a new String of `len` bytes from `off`. Both are already in range.
  sig [Value, Value, Value] => Value
  def zr_str_byteslice(s, off, len)
    zr_str_piece(s, RString.ptr(s) + zr_fix2long(off), zr_fix2long(len))
  end

  # A new String of the `len` bytes at `bytes`, which are in `src`, with
  # the encoding of `src`. Bytes from a plain ASCII String are plain ASCII
  # too, so the piece gets that scan's results with no scan of its own.
  sig [Value, Ptr, Word] => Value
  def zr_str_piece(src, bytes, len)
    out = zr_str_copy_encoding(zr_str_new(bytes, len), src)
    if (RBasic.flags(src) & FL_ASCII) != 0
      RBasic.set_flags(out, RBasic.flags(out) | FL_ASCII | FL_SCANNED | FL_VALID)
    end
    out
  end

  # Replaces the bytes of the receiver with the bytes of `other`.
  sig [Value, Value] => Value
  def zr_str_replace(s, other)
    if zr_modify_frozen_p(s)
      return zr_frozen_error(s)
    end
    zr_str_take_bytes(s, other)
    zr_str_modified(s)
    zr_str_copy_encoding(s, other)
  end

  # `setbyte`: sets the byte at the fixnum `i` to the fixnum `byte` modulo
  # 256. An index out of range raises before a frozen String does, in the
  # same order as rb_str_setbyte checks them.
  sig [Value, Value, Value] => Value
  def zr_str_setbyte(s, i, byte)
    n = zr_fix2long(i)
    if n < 0
      n += RString.len(s)
    end
    if n >= 0 && n < RString.len(s) && zr_modify_frozen_p(s)
      return zr_frozen_error(s)
    end
    if n < 0 || n >= RString.len(s)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("index "), 6)
      zr_buf_long(b, zr_fix2long(i))
      zr_buf_push(b, Machine.bytes(" out of string"), 14)
      return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
    end
    Machine.store8(RString.ptr(s) + n, 0, Machine.i8(zr_fix2long(byte) & 255))
    zr_str_modified(s)
    byte
  end

  # Returns a String of one byte.
  sig [Value] => Value
  def zr_str_from_byte(byte)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, zr_fix2long(byte) & 255)
    s = zr_buf_take(b)
    if zr_fix2long(byte) >= 128
      zr_str_set_binary(s)
    end
    s
  end

  # Returns the byte index of `needle` at or after `start`, or nil.
  sig [Value, Value, Value] => Value
  def zr_str_find_from(s, needle, start)
    i = zr_str_find(s, needle, zr_fix2long(start))
    if i < 0
      return Machine.value(QNIL)
    end
    zr_fix(i)
  end

  # Returns the first `n` bytes of `s` as a new String, and moves the rest
  # to the front of `s`. Thus a read buffer gives out a line and does not
  # copy the rest into a new String. Fewer bytes stay plain ASCII if all of
  # them were, so FL_ASCII stays correct.
  sig [Value, Value] => Value
  def zr_str_shift_front(s, n)
    len = RString.len(s)
    k = zr_fix2long(n)
    if k > len
      k = len
    end
    if k < 0
      k = 0
    end
    out = zr_str_piece(s, RString.ptr(s), k)
    flags = RBasic.flags(s) & FL_SNAPSHOT_CLEAR
    gap = zr_str_gap(s) + k
    # A malloc'd buffer moves its start past the bytes, so each line of a
    # read buffer costs no copy of the bytes after it.
    if (flags & FL_EMBED) == 0 && gap <= FL_GAP_MAX
      RString.set_ptr(s, RString.ptr(s) + k)
      RString.set_capa(s, RString.capa(s) - k)
      RString.set_len(s, len - k)
      RBasic.set_flags(s, (flags & FL_GAP_CLEAR) | (gap << FL_GAP_SHIFT))
      return out
    end
    RBasic.set_flags(s, flags)
    zr_memmove(RString.ptr(s), RString.ptr(s) + k, len - k)
    RString.set_len(s, len - k)
    Machine.store8(RString.ptr(s) + len - k, 0, Machine.i8(0))
    out
  end

  # Whitespace for strip and split: space and \t through \r, and NUL too
  # when `nul` is true (strip removes NUL, split does not).
  sig [Word, Value] => Bool
  def zr_space_byte_p(c, nul)
    c == 32 || (c >= 9 && c <= 13) || (c == 0 && nul == QTRUE)
  end

  # Returns the first offset at or after `from` whose byte is not
  # whitespace, or the length.
  sig [Value, Value, Value] => Value
  def zr_str_space_end(s, from, nul)
    n = RString.len(s)
    i = zr_fix2long(from)
    while i < n && zr_space_byte_p(Machine.u8(Machine.load8(RString.ptr(s) + i, 0)), nul)
      i += 1
    end
    zr_fix(i)
  end

  # Returns the first offset at or after `from` whose byte splits words,
  # or the length. Eight bytes with none below 0x21 contain no blank
  # (`zr_blank_word_p`); the code checks the rest one byte at a time.
  sig [Value, Value] => Value
  def zr_str_word_end(s, from)
    n = RString.len(s)
    i = zr_fix2long(from)
    p = RString.ptr(s)
    while i + 8 <= n && !zr_blank_word_p(Machine.load64(p + i, 0))
      i += 8
    end
    while i < n && !zr_space_byte_p(Machine.u8(Machine.load8(p + i, 0)), Machine.value(QFALSE))
      i += 1
    end
    zr_fix(i)
  end

  # Whether a byte of the word `w` can be a blank: any byte below 0x21, by
  # the carry trick. The trick can also say yes for a byte at or above
  # 0x80, so the caller then checks the bytes.
  sig [Word] => Bool
  def zr_blank_word_p(w)
    (Machine.sub_wrap(w, 0x2121212121212121) & (w ^ (0 - 1)) & Machine.word(0x8080808080808080)) != 0
  end

  # Returns the start of the whitespace that ends at offset `to`.
  sig [Value, Value, Value] => Value
  def zr_str_space_start(s, to, nul)
    i = zr_fix2long(to)
    while i > 0 && zr_space_byte_p(Machine.u8(Machine.load8(RString.ptr(s) + i - 1, 0)), nul)
      i -= 1
    end
    zr_fix(i)
  end

  # `[]=` and `insert` in place: replaces the `len` bytes at `from` with
  # the bytes of `other`, and moves the bytes after them once, as
  # rb_str_update_1 splices. A copy of the whole string for each change
  # would make a loop of small changes quadratic in the string's size.
  sig [Value, Value, Value, Value] => Value
  def zr_str_splice(s, from, len, other)
    if zr_modify_frozen_p(s)
      return zr_frozen_error(s)
    end
    if zr_str_join_incompatible_p(s, other)
      return zr_str_join_incompatible(s, other)
    end
    index = zr_str_join_index(s, other)
    # ASCII spliced into ASCII stays ASCII, as rb_str_update_1 keeps the
    # 7-bit coderange. Without the flag, the next index scans the whole string.
    ascii = (RBasic.flags(s) & FL_ASCII) != 0 && zr_str_ascii_bytes_p(other)
    at = zr_fix2long(from)
    cut = zr_fix2long(len)
    m = RString.len(other)
    old = RString.len(s)
    n = old - cut + m
    # When a String is spliced into itself, the code reads its bytes before
    # any of them move.
    src = RString.ptr(other)
    if Machine.word(other) == Machine.word(s)
      src = zr_xmalloc(m + 1)
      zr_memcpy(src, RString.ptr(s), m)
    end
    zr_str_reserve(s, n)
    if m != cut
      zr_memmove(RString.ptr(s) + at + m, RString.ptr(s) + at + cut, old - at - cut)
    end
    zr_memmove(RString.ptr(s) + at, src, m)
    if Machine.word(other) == Machine.word(s)
      zr_xfree(src)
    end
    RString.set_len(s, n)
    Machine.store8(RString.ptr(s) + n, 0, Machine.i8(0))
    if !ascii
      zr_str_modified(s)
    end
    zr_str_set_index(s, index)
    s
  end

  # Appends one byte as it is, and does not change the flags
  # (`append_as_bytes`).
  sig [Value, Value] => Value
  def zr_str_push_byte(recv, byte)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    n = RString.len(recv) + 1
    zr_str_reserve(recv, n)
    Machine.store8(RString.ptr(recv) + RString.len(recv), 0, Machine.i8(zr_fix2long(byte)))
    RString.set_len(recv, n)
    Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
    if (zr_fix2long(byte) & 255) >= 128
      zr_str_modified(recv)
    end
    if zr_str_encoding_index(recv) == ENC_USASCII && zr_fix2long(byte) >= 128
      zr_str_set_index(recv, ENC_UTF8)
    end
    recv
  end

  # Returns the address of the bytes of a string, for the `p` and `P` pack
  # directives.
  sig [Value] => Value
  def zr_str_bytes_address(s)
    zr_fix(Machine.word(RString.ptr(s)))
  end
end
