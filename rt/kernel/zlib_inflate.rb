# inflate.c: the decompressor, a machine over the modes below that
# makes what progress the input and the output room allow, then
# answers. The C keeps its registers in locals across one big switch;
# here each group of modes is a def over a cursor the driver owns, and
# a def answers whether the machine goes on, leaves, or has an answer
# of its own. No gzip header is ever asked for (inflateGetHeader is not
# reached), so the header fields are read and dropped.
# Derived from zlib; the license is in rt/kernel/zlib.rb.
Machine.struct :InflateState, strm: Ptr, mode: Word, last: Word, wrap: Word, havedict: Word, flags: Word, dmax: Word, check: Word, total: Word, wbits: Word, wsize: Word, whave: Word, wnext: Word, window: Ptr, hold: Ptr, bits: Word, length: Word, offset: Word, extra: Word, lencode: Ptr, distcode: Ptr, lenbits: Word, distbits: Word, ncode: Word, nlen: Word, ndist: Word, have: Word, nxt: Ptr, lens: Ptr, work: Ptr, codes: Ptr, sane: Word, back: Word, was: Word

# The registers of one inflate call: the C's next, have, put, left,
# hold and bits, the input and output room it began with, the flush
# mode, and the answer so far.
Machine.struct :InfCursor, nxt: Ptr, have: Word, put: Ptr, left: Word, hold: Ptr, bits: Word, in: Word, out: Word, flush: Word, ret: Word

# The modes, in the C's order and numbering; the order carries meaning,
# as inf_leave compares against BAD and CHECK.
INF_HEAD = 16180
INF_FLAGS = 16181
INF_TIME = 16182
INF_OS = 16183
INF_EXLEN = 16184
INF_EXTRA = 16185
INF_NAME = 16186
INF_COMMENT = 16187
INF_HCRC = 16188
INF_DICTID = 16189
INF_DICT = 16190
INF_TYPE = 16191
INF_TYPEDO = 16192
INF_STORED = 16193
INF_COPY_ = 16194
INF_COPY = 16195
INF_TABLE = 16196
INF_LENLENS = 16197
INF_CODELENS = 16198
INF_LEN_ = 16199
INF_LEN = 16200
INF_LENEXT = 16201
INF_DIST = 16202
INF_DISTEXT = 16203
INF_MATCH = 16204
INF_LIT = 16205
INF_CHECK = 16206
INF_LENGTH = 16207
INF_DONE = 16208
INF_BAD = 16209
INF_MEM = 16210
INF_SYNC = 16211

# What a mode def answers the driver.
INF_NEXT = 0
INF_LEAVE = 1
INF_RETURN = 2

# The state block: the struct, then lens (320 words), work (288 words)
# and codes (ENOUGH words).
INF_LENS_WORDS = 320
INF_WORK_WORDS = 288

# inflateStateCheck: 1 when `strm` has no state to speak of.
sig [Ptr] => Word
machine def zr_inflate_state_check(strm)
  if strm == 0
    return 1
  end
  st = ZStream.state(strm)
  if st == 0 || InflateState.strm(st) != strm || InflateState.mode(st) < INF_HEAD || InflateState.mode(st) > INF_SYNC
    return 1
  end
  0
end

# inflateResetKeep: the stream back at its start, its window kept.
sig [Ptr] => Word
machine def zr_inflate_reset_keep(strm)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  ZStream.set_total_in(strm, 0)
  ZStream.set_total_out(strm, 0)
  InflateState.set_total(st, 0)
  ZStream.set_msg(strm, 0)
  if InflateState.wrap(st) != 0
    ZStream.set_adler(strm, InflateState.wrap(st) & 1)
  end
  InflateState.set_mode(st, INF_HEAD)
  InflateState.set_last(st, 0)
  InflateState.set_havedict(st, 0)
  InflateState.set_flags(st, 0 - 1)
  InflateState.set_dmax(st, 32768)
  InflateState.set_hold(st, 0)
  InflateState.set_bits(st, 0)
  InflateState.set_lencode(st, InflateState.codes(st))
  InflateState.set_distcode(st, InflateState.codes(st))
  InflateState.set_nxt(st, InflateState.codes(st))
  InflateState.set_sane(st, 1)
  InflateState.set_back(st, 0 - 1)
  Z_OK
end

# inflateReset: the stream back at its start, its window forgotten.
sig [Ptr] => Word
machine def zr_inflate_reset(strm)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  InflateState.set_wsize(st, 0)
  InflateState.set_whave(st, 0)
  InflateState.set_wnext(st, 0)
  zr_inflate_reset_keep(strm)
end

# inflateReset2: the stream reset with a new windowBits, which names
# the wrapper too: negative for raw, 16 added for gzip, 32 added to
# take either, 0 to take the window size from the header.
sig [Ptr, Word] => Word
machine def zr_inflate_reset2(strm, window_bits)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  wrap = 0
  if window_bits < 0
    if window_bits < 0 - 15
      return Z_STREAM_ERROR
    end
    wrap = 0
    window_bits = 0 - window_bits
  else
    wrap = (window_bits >> 4) + 5
    if window_bits < 48
      window_bits = window_bits & 15
    end
  end
  if window_bits != 0 && (window_bits < 8 || window_bits > 15)
    return Z_STREAM_ERROR
  end
  if InflateState.window(st) != 0 && InflateState.wbits(st) != window_bits
    free(InflateState.window(st))
    InflateState.set_window(st, 0)
  end
  InflateState.set_wrap(st, wrap)
  InflateState.set_wbits(st, window_bits)
  zr_inflate_reset(strm)
end

# inflateInit2_: a stream given its state. The version and size checks
# are the C's guard against a caller built for another zlib, which
# nothing here can be.
sig [Ptr, Word] => Word
machine def zr_inflate_init2(strm, window_bits)
  if strm == 0
    return Z_STREAM_ERROR
  end
  ZStream.set_msg(strm, 0)
  size = InflateState.size + (INF_LENS_WORDS * 4) + (INF_WORK_WORDS * 4) + (INF_ENOUGH * 4)
  st = malloc(size)
  if st == 0
    return Z_MEM_ERROR
  end
  memset(st, Machine.i32(0), size)
  ZStream.set_state(strm, st)
  InflateState.set_strm(st, strm)
  InflateState.set_window(st, 0)
  InflateState.set_lens(st, st + InflateState.size)
  InflateState.set_work(st, InflateState.lens(st) + (INF_LENS_WORDS * 4))
  InflateState.set_codes(st, InflateState.work(st) + (INF_WORK_WORDS * 4))
  InflateState.set_mode(st, INF_HEAD)
  ret = zr_inflate_reset2(strm, window_bits)
  if ret != Z_OK
    free(st)
    ZStream.set_state(strm, 0)
  end
  ret
end

# inflateEnd: the state and its window freed.
sig [Ptr] => Word
machine def zr_inflate_end(strm)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  if InflateState.window(st) != 0
    free(InflateState.window(st))
  end
  free(st)
  ZStream.set_state(strm, 0)
  Z_OK
end

# fixedtables: the decoding tables of a fixed-code block.
sig [Ptr] => Void
machine def zr_inflate_fixed_tables(st)
  InflateState.set_lencode(st, zr_inflate_lenfix())
  InflateState.set_lenbits(st, 9)
  InflateState.set_distcode(st, zr_inflate_distfix())
  InflateState.set_distbits(st, 5)
end

# updatewindow: the last wsize bytes of output before `end_`, `copy`
# of them written this call, into the sliding window, which is made
# on first use. Answers 1 when the window cannot be made.
sig [Ptr, Ptr, Ptr, Word] => Word
machine def zr_inflate_update_window(strm, st, end_, copy)
  if InflateState.window(st) == 0
    window = malloc(1 << InflateState.wbits(st))
    if window == 0
      return 1
    end
    InflateState.set_window(st, window)
  end
  if InflateState.wsize(st) == 0
    InflateState.set_wsize(st, 1 << InflateState.wbits(st))
    InflateState.set_wnext(st, 0)
    InflateState.set_whave(st, 0)
  end
  wsize = InflateState.wsize(st)
  wnext = InflateState.wnext(st)
  window = InflateState.window(st)
  if copy >= wsize
    memmove(window, end_ - wsize, wsize)
    InflateState.set_wnext(st, 0)
    InflateState.set_whave(st, wsize)
  else
    dist = wsize - wnext
    if dist > copy
      dist = copy
    end
    memmove(window + wnext, end_ - copy, dist)
    copy -= dist
    if copy != 0
      memmove(window, end_ - copy, copy)
      InflateState.set_wnext(st, copy)
      InflateState.set_whave(st, wsize)
    else
      wnext += dist
      if wnext == wsize
        wnext = 0
      end
      InflateState.set_wnext(st, wnext)
      if InflateState.whave(st) < wsize
        InflateState.set_whave(st, InflateState.whave(st) + dist)
      end
    end
  end
  0
end

# UPDATE_CHECK: the running check, a crc32 under a gzip wrapper and an
# adler32 under a zlib one.
sig [Ptr, Word, Ptr, Word] => Word
machine def zr_inflate_update_check(st, check, buf, len)
  if InflateState.flags(st) != 0
    return zr_crc32(check, buf, len)
  end
  zr_adler32(check, buf, len)
end

# CRC2 and CRC4: `n` low bytes of `word` into the header's check.
sig [Ptr, Word, Word] => Void
machine def zr_inflate_crc_header(st, word, n)
  hbuf = Machine.slot(8)
  Machine.store8(hbuf, 0, Machine.i8(word))
  Machine.store8(hbuf, 1, Machine.i8(word >> 8))
  Machine.store8(hbuf, 2, Machine.i8(word >> 16))
  Machine.store8(hbuf, 3, Machine.i8(word >> 24))
  InflateState.set_check(st, zr_crc32(InflateState.check(st), hbuf, n))
end

# The stream's registers back from the cursor: the C's RESTORE.
sig [Ptr, Ptr, Ptr] => Void
machine def zr_inf_restore(strm, st, cur)
  ZStream.set_next_out(strm, InfCursor.put(cur))
  ZStream.set_avail_out(strm, InfCursor.left(cur))
  ZStream.set_next_in(strm, InfCursor.nxt(cur))
  ZStream.set_avail_in(strm, InfCursor.have(cur))
  InflateState.set_hold(st, InfCursor.hold(cur))
  InflateState.set_bits(st, InfCursor.bits(cur))
end

# The cursor from the stream's registers: the C's LOAD.
sig [Ptr, Ptr, Ptr] => Void
machine def zr_inf_load(strm, st, cur)
  InfCursor.set_put(cur, ZStream.next_out(strm))
  InfCursor.set_left(cur, ZStream.avail_out(strm))
  InfCursor.set_nxt(cur, ZStream.next_in(strm))
  InfCursor.set_have(cur, ZStream.avail_in(strm))
  InfCursor.set_hold(cur, InflateState.hold(st))
  InfCursor.set_bits(cur, InflateState.bits(st))
end

# PULLBYTE: one more input byte into the bit buffer, or false when
# there is none, which is when inflate leaves.
sig [Ptr] => Bool
machine def zr_inf_pull(cur)
  have = InfCursor.have(cur)
  if have == 0
    return false
  end
  InfCursor.set_have(cur, have - 1)
  nxt = InfCursor.nxt(cur)
  InfCursor.set_hold(cur, InfCursor.hold(cur) + (Machine.ptr(zr_zlib_byte(nxt)) << InfCursor.bits(cur)))
  InfCursor.set_nxt(cur, nxt + 1)
  InfCursor.set_bits(cur, InfCursor.bits(cur) + 8)
  true
end

# NEEDBITS: at least `n` bits in the buffer, or false when the input
# ran out first.
sig [Ptr, Word] => Bool
machine def zr_inf_need(cur, n)
  while InfCursor.bits(cur) < n
    if !zr_inf_pull(cur)
      return false
    end
  end
  true
end

# BITS: the low `n` bits of the buffer.
sig [Ptr, Word] => Word
machine def zr_inf_bits(cur, n)
  Machine.word(InfCursor.hold(cur) & ((1 << n) - 1))
end

# DROPBITS
sig [Ptr, Word] => Void
machine def zr_inf_drop(cur, n)
  InfCursor.set_hold(cur, InfCursor.hold(cur) >> n)
  InfCursor.set_bits(cur, InfCursor.bits(cur) - n)
end

# INITBITS
sig [Ptr] => Void
machine def zr_inf_init_bits(cur)
  InfCursor.set_hold(cur, 0)
  InfCursor.set_bits(cur, 0)
end

# BYTEBITS: the buffer at a byte boundary.
sig [Ptr] => Void
machine def zr_inf_byte_bits(cur)
  n = InfCursor.bits(cur) & 7
  InfCursor.set_hold(cur, InfCursor.hold(cur) >> n)
  InfCursor.set_bits(cur, InfCursor.bits(cur) - n)
end

# A data error: its message on the stream, and the BAD mode.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inf_bad(strm, st, msg)
  ZStream.set_msg(strm, msg)
  InflateState.set_mode(st, INF_BAD)
  INF_NEXT
end

# The HEAD mode: no wrapper, a gzip header's first two bytes, or a zlib
# header.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_head(strm, st, cur)
  if InflateState.wrap(st) == 0
    InflateState.set_mode(st, INF_TYPEDO)
    return INF_NEXT
  end
  if !zr_inf_need(cur, 16)
    return INF_LEAVE
  end
  hold = Machine.word(InfCursor.hold(cur))
  if (InflateState.wrap(st) & 2) != 0 && hold == 35615
    if InflateState.wbits(st) == 0
      InflateState.set_wbits(st, 15)
    end
    InflateState.set_check(st, 0)
    zr_inflate_crc_header(st, hold, 2)
    zr_inf_init_bits(cur)
    InflateState.set_mode(st, INF_FLAGS)
    return INF_NEXT
  end
  if (InflateState.wrap(st) & 1) == 0 || ((zr_inf_bits(cur, 8) << 8) + (hold >> 8)) % 31 != 0
    return zr_inf_bad(strm, st, Machine.bytes("incorrect header check\0"))
  end
  if zr_inf_bits(cur, 4) != Z_DEFLATED
    return zr_inf_bad(strm, st, Machine.bytes("unknown compression method\0"))
  end
  zr_inf_drop(cur, 4)
  len = zr_inf_bits(cur, 4) + 8
  if InflateState.wbits(st) == 0
    InflateState.set_wbits(st, len)
  end
  if len > 15 || len > InflateState.wbits(st)
    return zr_inf_bad(strm, st, Machine.bytes("invalid window size\0"))
  end
  InflateState.set_dmax(st, 1 << len)
  InflateState.set_flags(st, 0)
  InflateState.set_check(st, 1)
  ZStream.set_adler(strm, 1)
  if (Machine.word(InfCursor.hold(cur)) & 512) != 0
    InflateState.set_mode(st, INF_DICTID)
  else
    InflateState.set_mode(st, INF_TYPE)
  end
  zr_inf_init_bits(cur)
  INF_NEXT
end

# The FLAGS through HCRC modes: a gzip header read and, when it asks,
# checked. No header struct waits for its fields.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_gzip_header(strm, st, cur)
  mode = InflateState.mode(st)
  if mode == INF_FLAGS
    if !zr_inf_need(cur, 16)
      return INF_LEAVE
    end
    flags = Machine.word(InfCursor.hold(cur))
    InflateState.set_flags(st, flags)
    if (flags & 255) != Z_DEFLATED
      return zr_inf_bad(strm, st, Machine.bytes("unknown compression method\0"))
    end
    if (flags & 57344) != 0
      return zr_inf_bad(strm, st, Machine.bytes("unknown header flags set\0"))
    end
    if (flags & 512) != 0 && (InflateState.wrap(st) & 4) != 0
      zr_inflate_crc_header(st, flags, 2)
    end
    zr_inf_init_bits(cur)
    mode = INF_TIME
    InflateState.set_mode(st, mode)
  end
  if mode == INF_TIME
    if !zr_inf_need(cur, 32)
      return INF_LEAVE
    end
    if (InflateState.flags(st) & 512) != 0 && (InflateState.wrap(st) & 4) != 0
      zr_inflate_crc_header(st, Machine.word(InfCursor.hold(cur)), 4)
    end
    zr_inf_init_bits(cur)
    mode = INF_OS
    InflateState.set_mode(st, mode)
  end
  if mode == INF_OS
    if !zr_inf_need(cur, 16)
      return INF_LEAVE
    end
    if (InflateState.flags(st) & 512) != 0 && (InflateState.wrap(st) & 4) != 0
      zr_inflate_crc_header(st, Machine.word(InfCursor.hold(cur)), 2)
    end
    zr_inf_init_bits(cur)
    mode = INF_EXLEN
    InflateState.set_mode(st, mode)
  end
  if mode == INF_EXLEN
    if (InflateState.flags(st) & 1024) != 0
      if !zr_inf_need(cur, 16)
        return INF_LEAVE
      end
      InflateState.set_length(st, Machine.word(InfCursor.hold(cur)))
      if (InflateState.flags(st) & 512) != 0 && (InflateState.wrap(st) & 4) != 0
        zr_inflate_crc_header(st, Machine.word(InfCursor.hold(cur)), 2)
      end
      zr_inf_init_bits(cur)
    end
    mode = INF_EXTRA
    InflateState.set_mode(st, mode)
  end
  if mode == INF_EXTRA
    if (InflateState.flags(st) & 1024) != 0
      copy = InflateState.length(st)
      if copy > InfCursor.have(cur)
        copy = InfCursor.have(cur)
      end
      if copy != 0
        if (InflateState.flags(st) & 512) != 0 && (InflateState.wrap(st) & 4) != 0
          InflateState.set_check(st, zr_crc32(InflateState.check(st), InfCursor.nxt(cur), copy))
        end
        InfCursor.set_have(cur, InfCursor.have(cur) - copy)
        InfCursor.set_nxt(cur, InfCursor.nxt(cur) + copy)
        InflateState.set_length(st, InflateState.length(st) - copy)
      end
      if InflateState.length(st) != 0
        return INF_LEAVE
      end
    end
    InflateState.set_length(st, 0)
    mode = INF_NAME
    InflateState.set_mode(st, mode)
  end
  if mode == INF_NAME
    if (InflateState.flags(st) & 2048) != 0
      if !zr_inflate_skip_string(st, cur)
        return INF_LEAVE
      end
    end
    InflateState.set_length(st, 0)
    mode = INF_COMMENT
    InflateState.set_mode(st, mode)
  end
  if mode == INF_COMMENT
    if (InflateState.flags(st) & 4096) != 0
      if !zr_inflate_skip_string(st, cur)
        return INF_LEAVE
      end
    end
    mode = INF_HCRC
    InflateState.set_mode(st, mode)
  end
  if (InflateState.flags(st) & 512) != 0
    if !zr_inf_need(cur, 16)
      return INF_LEAVE
    end
    if (InflateState.wrap(st) & 4) != 0 && Machine.word(InfCursor.hold(cur)) != (InflateState.check(st) & 65535)
      return zr_inf_bad(strm, st, Machine.bytes("header crc mismatch\0"))
    end
    zr_inf_init_bits(cur)
  end
  InflateState.set_check(st, 0)
  ZStream.set_adler(strm, 0)
  InflateState.set_mode(st, INF_TYPE)
  INF_NEXT
end

# The NAME and COMMENT modes' work: a zero-terminated header string
# read past, counted into the check when the header asks. Answers
# false when the input ends before the string does.
sig [Ptr, Ptr] => Bool
machine def zr_inflate_skip_string(st, cur)
  have = InfCursor.have(cur)
  if have == 0
    return false
  end
  nxt = InfCursor.nxt(cur)
  copy = 0
  len = 0
  while true
    len = zr_zlib_byte(nxt + copy)
    copy += 1
    if len == 0 || copy >= have
      break
    end
  end
  if (InflateState.flags(st) & 512) != 0 && (InflateState.wrap(st) & 4) != 0
    InflateState.set_check(st, zr_crc32(InflateState.check(st), nxt, copy))
  end
  InfCursor.set_have(cur, have - copy)
  InfCursor.set_nxt(cur, nxt + copy)
  len == 0
end

# The DICTID and DICT modes: the dictionary's check read, and the
# caller told to set the dictionary when none has been.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_dict(strm, st, cur)
  if InflateState.mode(st) == INF_DICTID
    if !zr_inf_need(cur, 32)
      return INF_LEAVE
    end
    check = zr_zlib_swap32(Machine.word(InfCursor.hold(cur)))
    InflateState.set_check(st, check)
    ZStream.set_adler(strm, check)
    zr_inf_init_bits(cur)
    InflateState.set_mode(st, INF_DICT)
  end
  if InflateState.havedict(st) == 0
    zr_inf_restore(strm, st, cur)
    InfCursor.set_ret(cur, Z_NEED_DICT)
    return INF_RETURN
  end
  InflateState.set_check(st, 1)
  ZStream.set_adler(strm, 1)
  InflateState.set_mode(st, INF_TYPE)
  INF_NEXT
end

# The TYPE, TYPEDO, STORED, COPY_ and COPY modes: a block's header, and
# a stored block's bytes.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_type(strm, st, cur)
  mode = InflateState.mode(st)
  flush = InfCursor.flush(cur)
  if mode == INF_TYPE
    if flush == Z_BLOCK || flush == Z_TREES
      return INF_LEAVE
    end
    mode = INF_TYPEDO
  end
  if mode == INF_TYPEDO
    if InflateState.last(st) != 0
      zr_inf_byte_bits(cur)
      InflateState.set_mode(st, INF_CHECK)
      return INF_NEXT
    end
    if !zr_inf_need(cur, 3)
      return INF_LEAVE
    end
    InflateState.set_last(st, zr_inf_bits(cur, 1))
    zr_inf_drop(cur, 1)
    kind = zr_inf_bits(cur, 2)
    if kind == 0
      InflateState.set_mode(st, INF_STORED)
    elsif kind == 1
      zr_inflate_fixed_tables(st)
      InflateState.set_mode(st, INF_LEN_)
      if flush == Z_TREES
        zr_inf_drop(cur, 2)
        return INF_LEAVE
      end
    elsif kind == 2
      InflateState.set_mode(st, INF_TABLE)
    else
      ZStream.set_msg(strm, Machine.bytes("invalid block type\0"))
      InflateState.set_mode(st, INF_BAD)
    end
    zr_inf_drop(cur, 2)
    return INF_NEXT
  end
  if mode == INF_STORED
    zr_inf_byte_bits(cur)
    if !zr_inf_need(cur, 32)
      return INF_LEAVE
    end
    hold = Machine.word(InfCursor.hold(cur))
    if (hold & 65535) != ((hold >> 16) ^ 65535)
      return zr_inf_bad(strm, st, Machine.bytes("invalid stored block lengths\0"))
    end
    InflateState.set_length(st, hold & 65535)
    zr_inf_init_bits(cur)
    mode = INF_COPY_
    InflateState.set_mode(st, mode)
    if flush == Z_TREES
      return INF_LEAVE
    end
  end
  if mode == INF_COPY_
    mode = INF_COPY
    InflateState.set_mode(st, mode)
  end
  copy = InflateState.length(st)
  if copy != 0
    if copy > InfCursor.have(cur)
      copy = InfCursor.have(cur)
    end
    if copy > InfCursor.left(cur)
      copy = InfCursor.left(cur)
    end
    if copy == 0
      return INF_LEAVE
    end
    memmove(InfCursor.put(cur), InfCursor.nxt(cur), copy)
    InfCursor.set_have(cur, InfCursor.have(cur) - copy)
    InfCursor.set_nxt(cur, InfCursor.nxt(cur) + copy)
    InfCursor.set_left(cur, InfCursor.left(cur) - copy)
    InfCursor.set_put(cur, InfCursor.put(cur) + copy)
    InflateState.set_length(st, InflateState.length(st) - copy)
    return INF_NEXT
  end
  InflateState.set_mode(st, INF_TYPE)
  INF_NEXT
end

# The table pointer and root bits handed to inflate_table through
# cells, and taken back.
sig [Ptr, Word, Word, Word] => Word
machine def zr_inflate_build(st, type, codes, root)
  table = Machine.slot(8)
  bits = Machine.slot(8)
  Machine.store64(table, 0, Machine.word(InflateState.nxt(st)))
  Machine.store64(bits, 0, root)
  lens = InflateState.lens(st)
  if type == INF_DISTS
    lens += InflateState.nlen(st) * 4
  end
  ret = zr_inflate_table(type, lens, codes, table, bits, InflateState.work(st))
  InflateState.set_nxt(st, Machine.ptr(Machine.load64(table, 0)))
  if type == INF_DISTS
    InflateState.set_distbits(st, Machine.load64(bits, 0))
  else
    InflateState.set_lenbits(st, Machine.load64(bits, 0))
  end
  ret
end

# A code from `table` for the low bits of the buffer, pulling input
# until the code's bits are all there: answers the code, or -1 when the
# input ran out.
sig [Ptr, Ptr, Word] => Word
machine def zr_inflate_decode(cur, table, table_bits)
  while true
    here = zr_zlib_u32(table, zr_inf_bits(cur, table_bits))
    if zr_inf_code_bits(here) <= InfCursor.bits(cur)
      return here
    end
    if !zr_inf_pull(cur)
      return 0 - 1
    end
  end
  0
end

# The second-level code under `last`, pulling as needed: the code, or
# -1 when the input ran out.
sig [Ptr, Ptr, Word] => Word
machine def zr_inflate_decode_under(cur, table, last)
  while true
    here = zr_zlib_u32(table, zr_inf_code_val(last) + (zr_inf_bits(cur, zr_inf_code_bits(last) + zr_inf_code_op(last)) >> zr_inf_code_bits(last)))
    if zr_inf_code_bits(last) + zr_inf_code_bits(here) <= InfCursor.bits(cur)
      return here
    end
    if !zr_inf_pull(cur)
      return 0 - 1
    end
  end
  0
end

# The TABLE, LENLENS and CODELENS modes: a dynamic block's code lengths
# read and its tables built.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_table_lens(strm, st, cur)
  mode = InflateState.mode(st)
  lens = InflateState.lens(st)
  if mode == INF_TABLE
    if !zr_inf_need(cur, 14)
      return INF_LEAVE
    end
    InflateState.set_nlen(st, zr_inf_bits(cur, 5) + 257)
    zr_inf_drop(cur, 5)
    InflateState.set_ndist(st, zr_inf_bits(cur, 5) + 1)
    zr_inf_drop(cur, 5)
    InflateState.set_ncode(st, zr_inf_bits(cur, 4) + 4)
    zr_inf_drop(cur, 4)
    if InflateState.nlen(st) > 286 || InflateState.ndist(st) > 30
      return zr_inf_bad(strm, st, Machine.bytes("too many length or distance symbols\0"))
    end
    InflateState.set_have(st, 0)
    mode = INF_LENLENS
    InflateState.set_mode(st, mode)
  end
  if mode == INF_LENLENS
    order = zr_inflate_order()
    while InflateState.have(st) < InflateState.ncode(st)
      if !zr_inf_need(cur, 3)
        return INF_LEAVE
      end
      zr_zlib_set_u32(lens, zr_zlib_u32(order, InflateState.have(st)), zr_inf_bits(cur, 3))
      InflateState.set_have(st, InflateState.have(st) + 1)
      zr_inf_drop(cur, 3)
    end
    while InflateState.have(st) < 19
      zr_zlib_set_u32(lens, zr_zlib_u32(order, InflateState.have(st)), 0)
      InflateState.set_have(st, InflateState.have(st) + 1)
    end
    InflateState.set_nxt(st, InflateState.codes(st))
    InflateState.set_lencode(st, InflateState.codes(st))
    if zr_inflate_build(st, INF_CODES, 19, 7) != 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid code lengths set\0"))
    end
    InflateState.set_have(st, 0)
    mode = INF_CODELENS
    InflateState.set_mode(st, mode)
  end
  total = InflateState.nlen(st) + InflateState.ndist(st)
  while InflateState.have(st) < total
    here = zr_inflate_decode(cur, InflateState.lencode(st), InflateState.lenbits(st))
    if here < 0
      return INF_LEAVE
    end
    val = zr_inf_code_val(here)
    here_bits = zr_inf_code_bits(here)
    if val < 16
      zr_inf_drop(cur, here_bits)
      zr_zlib_set_u32(lens, InflateState.have(st), val)
      InflateState.set_have(st, InflateState.have(st) + 1)
    else
      len = 0
      copy = 0
      if val == 16
        if !zr_inf_need(cur, here_bits + 2)
          return INF_LEAVE
        end
        zr_inf_drop(cur, here_bits)
        if InflateState.have(st) == 0
          return zr_inf_bad(strm, st, Machine.bytes("invalid bit length repeat\0"))
        end
        len = zr_zlib_u32(lens, InflateState.have(st) - 1)
        copy = 3 + zr_inf_bits(cur, 2)
        zr_inf_drop(cur, 2)
      elsif val == 17
        if !zr_inf_need(cur, here_bits + 3)
          return INF_LEAVE
        end
        zr_inf_drop(cur, here_bits)
        len = 0
        copy = 3 + zr_inf_bits(cur, 3)
        zr_inf_drop(cur, 3)
      else
        if !zr_inf_need(cur, here_bits + 7)
          return INF_LEAVE
        end
        zr_inf_drop(cur, here_bits)
        len = 0
        copy = 11 + zr_inf_bits(cur, 7)
        zr_inf_drop(cur, 7)
      end
      if InflateState.have(st) + copy > total
        return zr_inf_bad(strm, st, Machine.bytes("invalid bit length repeat\0"))
      end
      while copy > 0
        zr_zlib_set_u32(lens, InflateState.have(st), len)
        InflateState.set_have(st, InflateState.have(st) + 1)
        copy -= 1
      end
    end
  end
  if zr_zlib_u32(lens, 256) == 0
    return zr_inf_bad(strm, st, Machine.bytes("invalid code -- missing end-of-block\0"))
  end
  InflateState.set_nxt(st, InflateState.codes(st))
  InflateState.set_lencode(st, InflateState.codes(st))
  if zr_inflate_build(st, INF_LENS, InflateState.nlen(st), 9) != 0
    return zr_inf_bad(strm, st, Machine.bytes("invalid literal/lengths set\0"))
  end
  InflateState.set_distcode(st, InflateState.nxt(st))
  if zr_inflate_build(st, INF_DISTS, InflateState.ndist(st), 6) != 0
    return zr_inf_bad(strm, st, Machine.bytes("invalid distances set\0"))
  end
  InflateState.set_mode(st, INF_LEN_)
  if InfCursor.flush(cur) == Z_TREES
    return INF_LEAVE
  end
  INF_NEXT
end

# The LEN_ through LIT modes: literals and matches decoded one at a
# time, or through inflate_fast while the buffers allow it.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_codes(strm, st, cur)
  mode = InflateState.mode(st)
  if mode == INF_LEN_
    mode = INF_LEN
    InflateState.set_mode(st, mode)
  end
  if mode == INF_LEN
    if InfCursor.have(cur) >= 6 && InfCursor.left(cur) >= 258
      zr_inf_restore(strm, st, cur)
      zr_inflate_fast(strm, InfCursor.out(cur))
      zr_inf_load(strm, st, cur)
      if InflateState.mode(st) == INF_TYPE
        InflateState.set_back(st, 0 - 1)
      end
      return INF_NEXT
    end
    InflateState.set_back(st, 0)
    here = zr_inflate_decode(cur, InflateState.lencode(st), InflateState.lenbits(st))
    if here < 0
      return INF_LEAVE
    end
    if zr_inf_code_op(here) != 0 && (zr_inf_code_op(here) & 240) == 0
      last = here
      here = zr_inflate_decode_under(cur, InflateState.lencode(st), last)
      if here < 0
        return INF_LEAVE
      end
      zr_inf_drop(cur, zr_inf_code_bits(last))
      InflateState.set_back(st, InflateState.back(st) + zr_inf_code_bits(last))
    end
    zr_inf_drop(cur, zr_inf_code_bits(here))
    InflateState.set_back(st, InflateState.back(st) + zr_inf_code_bits(here))
    InflateState.set_length(st, zr_inf_code_val(here))
    op = zr_inf_code_op(here)
    if op == 0
      InflateState.set_mode(st, INF_LIT)
      return INF_NEXT
    end
    if (op & 32) != 0
      InflateState.set_back(st, 0 - 1)
      InflateState.set_mode(st, INF_TYPE)
      return INF_NEXT
    end
    if (op & 64) != 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid literal/length code\0"))
    end
    InflateState.set_extra(st, op & 15)
    mode = INF_LENEXT
    InflateState.set_mode(st, mode)
  end
  if mode == INF_LENEXT
    extra = InflateState.extra(st)
    if extra != 0
      if !zr_inf_need(cur, extra)
        return INF_LEAVE
      end
      InflateState.set_length(st, InflateState.length(st) + zr_inf_bits(cur, extra))
      zr_inf_drop(cur, extra)
      InflateState.set_back(st, InflateState.back(st) + extra)
    end
    InflateState.set_was(st, InflateState.length(st))
    mode = INF_DIST
    InflateState.set_mode(st, mode)
  end
  if mode == INF_DIST
    here = zr_inflate_decode(cur, InflateState.distcode(st), InflateState.distbits(st))
    if here < 0
      return INF_LEAVE
    end
    if (zr_inf_code_op(here) & 240) == 0
      last = here
      here = zr_inflate_decode_under(cur, InflateState.distcode(st), last)
      if here < 0
        return INF_LEAVE
      end
      zr_inf_drop(cur, zr_inf_code_bits(last))
      InflateState.set_back(st, InflateState.back(st) + zr_inf_code_bits(last))
    end
    zr_inf_drop(cur, zr_inf_code_bits(here))
    InflateState.set_back(st, InflateState.back(st) + zr_inf_code_bits(here))
    if (zr_inf_code_op(here) & 64) != 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid distance code\0"))
    end
    InflateState.set_offset(st, zr_inf_code_val(here))
    InflateState.set_extra(st, zr_inf_code_op(here) & 15)
    mode = INF_DISTEXT
    InflateState.set_mode(st, mode)
  end
  if mode == INF_DISTEXT
    extra = InflateState.extra(st)
    if extra != 0
      if !zr_inf_need(cur, extra)
        return INF_LEAVE
      end
      InflateState.set_offset(st, InflateState.offset(st) + zr_inf_bits(cur, extra))
      zr_inf_drop(cur, extra)
      InflateState.set_back(st, InflateState.back(st) + extra)
    end
    mode = INF_MATCH
    InflateState.set_mode(st, mode)
  end
  if mode == INF_MATCH
    left = InfCursor.left(cur)
    if left == 0
      return INF_LEAVE
    end
    put = InfCursor.put(cur)
    copy = InfCursor.out(cur) - left
    from = put
    if InflateState.offset(st) > copy
      copy = InflateState.offset(st) - copy
      if copy > InflateState.whave(st)
        if InflateState.sane(st) != 0
          return zr_inf_bad(strm, st, Machine.bytes("invalid distance too far back\0"))
        end
      end
      if copy > InflateState.wnext(st)
        copy -= InflateState.wnext(st)
        from = InflateState.window(st) + (InflateState.wsize(st) - copy)
      else
        from = InflateState.window(st) + (InflateState.wnext(st) - copy)
      end
      if copy > InflateState.length(st)
        copy = InflateState.length(st)
      end
    else
      from = put - InflateState.offset(st)
      copy = InflateState.length(st)
    end
    if copy > left
      copy = left
    end
    InfCursor.set_left(cur, left - copy)
    InflateState.set_length(st, InflateState.length(st) - copy)
    zr_zlib_copy_bytes(put, from, copy)
    InfCursor.set_put(cur, put + copy)
    if InflateState.length(st) == 0
      InflateState.set_mode(st, INF_LEN)
    end
    return INF_NEXT
  end
  if InfCursor.left(cur) == 0
    return INF_LEAVE
  end
  Machine.store8(InfCursor.put(cur), 0, Machine.i8(InflateState.length(st)))
  InfCursor.set_put(cur, InfCursor.put(cur) + 1)
  InfCursor.set_left(cur, InfCursor.left(cur) - 1)
  InflateState.set_mode(st, INF_LEN)
  INF_NEXT
end

# The CHECK, LENGTH, DONE, BAD, MEM and SYNC modes: the trailer, and
# the ends of the road.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_inflate_check(strm, st, cur)
  mode = InflateState.mode(st)
  if mode == INF_CHECK
    if InflateState.wrap(st) != 0
      if !zr_inf_need(cur, 32)
        return INF_LEAVE
      end
      out = InfCursor.out(cur) - InfCursor.left(cur)
      ZStream.set_total_out(strm, ZStream.total_out(strm) + out)
      InflateState.set_total(st, InflateState.total(st) + out)
      if (InflateState.wrap(st) & 4) != 0 && out != 0
        check = zr_inflate_update_check(st, InflateState.check(st), InfCursor.put(cur) - out, out)
        InflateState.set_check(st, check)
        ZStream.set_adler(strm, check)
      end
      InfCursor.set_out(cur, InfCursor.left(cur))
      hold = Machine.word(InfCursor.hold(cur))
      if InflateState.flags(st) == 0
        hold = zr_zlib_swap32(hold)
      end
      if (InflateState.wrap(st) & 4) != 0 && hold != InflateState.check(st)
        return zr_inf_bad(strm, st, Machine.bytes("incorrect data check\0"))
      end
      zr_inf_init_bits(cur)
    end
    mode = INF_LENGTH
    InflateState.set_mode(st, mode)
  end
  if mode == INF_LENGTH
    if InflateState.wrap(st) != 0 && InflateState.flags(st) != 0
      if !zr_inf_need(cur, 32)
        return INF_LEAVE
      end
      if (InflateState.wrap(st) & 4) != 0 && Machine.word(InfCursor.hold(cur)) != (InflateState.total(st) & ZLIB_MASK32)
        return zr_inf_bad(strm, st, Machine.bytes("incorrect length check\0"))
      end
      zr_inf_init_bits(cur)
    end
    mode = INF_DONE
    InflateState.set_mode(st, mode)
  end
  if mode == INF_DONE
    InfCursor.set_ret(cur, Z_STREAM_END)
    return INF_LEAVE
  end
  if mode == INF_BAD
    InfCursor.set_ret(cur, Z_DATA_ERROR)
    return INF_LEAVE
  end
  if mode == INF_MEM
    InfCursor.set_ret(cur, Z_MEM_ERROR)
    return INF_RETURN
  end
  InfCursor.set_ret(cur, Z_STREAM_ERROR)
  INF_RETURN
end

# inflate: as much of the stream as its input and output room allow.
sig [Ptr, Word] => Word
machine def zr_inflate(strm, flush)
  if zr_inflate_state_check(strm) != 0 || ZStream.next_out(strm) == 0 || (ZStream.next_in(strm) == 0 && ZStream.avail_in(strm) != 0)
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  if InflateState.mode(st) == INF_TYPE
    InflateState.set_mode(st, INF_TYPEDO)
  end
  cur = Machine.slot(InfCursor.size)
  zr_inf_load(strm, st, cur)
  InfCursor.set_in(cur, InfCursor.have(cur))
  InfCursor.set_out(cur, InfCursor.left(cur))
  InfCursor.set_flush(cur, flush)
  InfCursor.set_ret(cur, Z_OK)
  step = INF_NEXT
  while step == INF_NEXT
    mode = InflateState.mode(st)
    if mode == INF_HEAD
      step = zr_inflate_head(strm, st, cur)
    elsif mode <= INF_HCRC
      step = zr_inflate_gzip_header(strm, st, cur)
    elsif mode <= INF_DICT
      step = zr_inflate_dict(strm, st, cur)
    elsif mode <= INF_COPY
      step = zr_inflate_type(strm, st, cur)
    elsif mode <= INF_CODELENS
      step = zr_inflate_table_lens(strm, st, cur)
    elsif mode <= INF_LIT
      step = zr_inflate_codes(strm, st, cur)
    else
      step = zr_inflate_check(strm, st, cur)
    end
  end
  if step == INF_RETURN
    return InfCursor.ret(cur)
  end
  zr_inf_restore(strm, st, cur)
  out = InfCursor.out(cur)
  mode = InflateState.mode(st)
  if InflateState.wsize(st) != 0 || (out != ZStream.avail_out(strm) && mode < INF_BAD && (mode < INF_CHECK || flush != Z_FINISH))
    if zr_inflate_update_window(strm, st, ZStream.next_out(strm), out - ZStream.avail_out(strm)) != 0
      InflateState.set_mode(st, INF_MEM)
      return Z_MEM_ERROR
    end
  end
  in_ = InfCursor.in(cur) - ZStream.avail_in(strm)
  out -= ZStream.avail_out(strm)
  ZStream.set_total_in(strm, ZStream.total_in(strm) + in_)
  ZStream.set_total_out(strm, ZStream.total_out(strm) + out)
  InflateState.set_total(st, InflateState.total(st) + out)
  if (InflateState.wrap(st) & 4) != 0 && out != 0
    check = zr_inflate_update_check(st, InflateState.check(st), ZStream.next_out(strm) - out, out)
    InflateState.set_check(st, check)
    ZStream.set_adler(strm, check)
  end
  data_type = InflateState.bits(st)
  if InflateState.last(st) != 0
    data_type += 64
  end
  if mode == INF_TYPE
    data_type += 128
  end
  if mode == INF_LEN_ || mode == INF_COPY_
    data_type += 256
  end
  ZStream.set_data_type(strm, data_type)
  ret = InfCursor.ret(cur)
  if ((in_ == 0 && out == 0) || flush == Z_FINISH) && ret == Z_OK
    ret = Z_BUF_ERROR
  end
  ret
end

# inflateSetDictionary: the dictionary a zlib stream named, or any
# dictionary for a raw stream, into the window.
sig [Ptr, Ptr, Word] => Word
machine def zr_inflate_set_dictionary(strm, dictionary, length)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  if InflateState.wrap(st) != 0 && InflateState.mode(st) != INF_DICT
    return Z_STREAM_ERROR
  end
  if InflateState.mode(st) == INF_DICT
    if zr_adler32(1, dictionary, length) != InflateState.check(st)
      return Z_DATA_ERROR
    end
  end
  if zr_inflate_update_window(strm, st, dictionary + length, length) != 0
    InflateState.set_mode(st, INF_MEM)
    return Z_MEM_ERROR
  end
  InflateState.set_havedict(st, 1)
  Z_OK
end

# syncsearch: `len` bytes at `buf` searched for 0, 0, 0xff, 0xff, the
# count found so far in the cell `have`; answers how many bytes were
# read.
sig [Ptr, Ptr, Word] => Word
machine def zr_inflate_sync_search(have, buf, len)
  got = Machine.load64(have, 0)
  nxt = 0
  while nxt < len && got < 4
    b = zr_zlib_byte(buf + nxt)
    want = 255
    if got < 2
      want = 0
    end
    if b == want
      got += 1
    elsif b != 0
      got = 0
    else
      got = 4 - got
    end
    nxt += 1
  end
  Machine.store64(have, 0, got)
  nxt
end

# inflateSync: the input searched for the next full flush point, and
# the stream set to go on from there.
sig [Ptr] => Word
machine def zr_inflate_sync(strm)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  if ZStream.avail_in(strm) == 0 && InflateState.bits(st) < 8
    return Z_BUF_ERROR
  end
  have = Machine.slot(8)
  if InflateState.mode(st) != INF_SYNC
    InflateState.set_mode(st, INF_SYNC)
    n = InflateState.bits(st) & 7
    InflateState.set_hold(st, InflateState.hold(st) >> n)
    InflateState.set_bits(st, InflateState.bits(st) - n)
    buf = Machine.slot(8)
    len = 0
    while InflateState.bits(st) >= 8
      Machine.store8(buf + len, 0, Machine.i8(Machine.word(InflateState.hold(st))))
      len += 1
      InflateState.set_hold(st, InflateState.hold(st) >> 8)
      InflateState.set_bits(st, InflateState.bits(st) - 8)
    end
    InflateState.set_have(st, 0)
    Machine.store64(have, 0, 0)
    zr_inflate_sync_search(have, buf, len)
    InflateState.set_have(st, Machine.load64(have, 0))
  end
  Machine.store64(have, 0, InflateState.have(st))
  len = zr_inflate_sync_search(have, ZStream.next_in(strm), ZStream.avail_in(strm))
  InflateState.set_have(st, Machine.load64(have, 0))
  ZStream.set_avail_in(strm, ZStream.avail_in(strm) - len)
  ZStream.set_next_in(strm, ZStream.next_in(strm) + len)
  ZStream.set_total_in(strm, ZStream.total_in(strm) + len)
  if InflateState.have(st) != 4
    return Z_DATA_ERROR
  end
  if InflateState.flags(st) == 0 - 1
    InflateState.set_wrap(st, 0)
  else
    InflateState.set_wrap(st, InflateState.wrap(st) & 3)
  end
  flags = InflateState.flags(st)
  in_ = ZStream.total_in(strm)
  out = ZStream.total_out(strm)
  zr_inflate_reset(strm)
  ZStream.set_total_in(strm, in_)
  ZStream.set_total_out(strm, out)
  InflateState.set_flags(st, flags)
  InflateState.set_mode(st, INF_TYPE)
  Z_OK
end

# inflateSyncPoint: whether the stream stands at the end of a block a
# sync or full flush wrote.
sig [Ptr] => Word
machine def zr_inflate_sync_point(strm)
  if zr_inflate_state_check(strm) != 0
    return Z_STREAM_ERROR
  end
  st = ZStream.state(strm)
  if InflateState.mode(st) == INF_STORED && InflateState.bits(st) == 0
    return 1
  end
  0
end
