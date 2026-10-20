# Derived from zlib 1.3.1 (Zlib); see THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # inflate.c: the decompressor. It is a state machine over the modes
  # below. It goes as far as the input and the output space allow, then
  # returns. The C keeps its registers in locals across one large switch.
  # Here each group of modes is a def that uses a cursor that the driver
  # owns. A def returns whether the machine continues, leaves, or has its
  # own return value. No caller asks for a gzip header (inflateGetHeader
  # is not used), so the header fields are read and discarded.
  # Derived from zlib. The license is in lib/zr/runtime/kernel/zlib.rb.
  class InflateState < Layout
    attr_accessor :strm #: ptr
    attr_accessor :mode #: word
    attr_accessor :last #: word
    attr_accessor :wrap #: word
    attr_accessor :havedict #: word
    attr_accessor :flags #: word
    attr_accessor :dmax #: word
    attr_accessor :check #: word
    attr_accessor :total #: word
    attr_accessor :wbits #: word
    attr_accessor :wsize #: word
    attr_accessor :whave #: word
    attr_accessor :wnext #: word
    attr_accessor :window #: ptr
    attr_accessor :hold #: ptr
    attr_accessor :bits #: word
    attr_accessor :length #: word
    attr_accessor :offset #: word
    attr_accessor :extra #: word
    attr_accessor :lencode #: ptr
    attr_accessor :distcode #: ptr
    attr_accessor :lenbits #: word
    attr_accessor :distbits #: word
    attr_accessor :ncode #: word
    attr_accessor :nlen #: word
    attr_accessor :ndist #: word
    attr_accessor :have #: word
    attr_accessor :nxt #: ptr
    attr_accessor :lens #: ptr
    attr_accessor :work #: ptr
    attr_accessor :codes #: ptr
    attr_accessor :sane #: word
    attr_accessor :back #: word
    attr_accessor :was #: word
  end

  # The registers of one inflate call: next, have, put, left, hold and
  # bits from the C, the input and output space at the start, the flush
  # mode, and the return value so far.
  class InfCursor < Layout
    attr_accessor :nxt #: ptr
    attr_accessor :have #: word
    attr_accessor :put #: ptr
    attr_accessor :left #: word
    attr_accessor :hold #: ptr
    attr_accessor :bits #: word
    attr_accessor :in #: word
    attr_accessor :out #: word
    attr_accessor :flush #: word
    attr_accessor :ret #: word
  end

  # The modes, with the order and numbers of the C. The order is
  # important, because inf_leave compares against BAD and CHECK.
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

  # The values that a mode def returns to the driver.
  INF_NEXT = 0
  INF_LEAVE = 1
  INF_RETURN = 2

  # The state block: the struct, then lens (320 words), work (288 words)
  # and codes (ENOUGH words).
  INF_LENS_WORDS = 320
  INF_WORK_WORDS = 288

  # inflateStateCheck: 1 when `strm` has no valid state.
  #: (ptr) -> word
  def zr_inflate_state_check(strm)
    if strm == 0
      return 1
    end
    st = ZStream[strm].state
    if st == 0 || InflateState[st].strm != strm || InflateState[st].mode < INF_HEAD || InflateState[st].mode > INF_SYNC
      return 1
    end
    0
  end

  # inflateResetKeep: resets the stream to its start, and keeps its window.
  #: (ptr) -> word
  def zr_inflate_reset_keep(strm)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    ZStream[strm].total_in = 0
    ZStream[strm].total_out = 0
    InflateState[st].total = 0
    ZStream[strm].msg = 0
    if InflateState[st].wrap != 0
      ZStream[strm].adler = InflateState[st].wrap & 1
    end
    InflateState[st].mode = INF_HEAD
    InflateState[st].last = 0
    InflateState[st].havedict = 0
    InflateState[st].flags = 0 - 1
    InflateState[st].dmax = 32768
    InflateState[st].hold = 0
    InflateState[st].bits = 0
    InflateState[st].lencode = InflateState[st].codes
    InflateState[st].distcode = InflateState[st].codes
    InflateState[st].nxt = InflateState[st].codes
    InflateState[st].sane = 1
    InflateState[st].back = 0 - 1
    Z_OK
  end

  # inflateReset: resets the stream to its start, and clears its window.
  #: (ptr) -> word
  def zr_inflate_reset(strm)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    InflateState[st].wsize = 0
    InflateState[st].whave = 0
    InflateState[st].wnext = 0
    zr_inflate_reset_keep(strm)
  end

  # inflateReset2: resets the stream with a new windowBits, which also
  # selects the wrapper: negative for raw, plus 16 for gzip, plus 32 for
  # either, 0 to take the window size from the header.
  #: (ptr, word) -> word
  def zr_inflate_reset2(strm, window_bits)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
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
    if InflateState[st].window != 0 && InflateState[st].wbits != window_bits
      Libc.free(InflateState[st].window)
      InflateState[st].window = 0
    end
    InflateState[st].wrap = wrap
    InflateState[st].wbits = window_bits
    zr_inflate_reset(strm)
  end

  # inflateInit2_: gives a stream its state. The C checks the version and
  # size to find a caller built for another zlib. Here no caller can be,
  # so these checks are not necessary.
  #: (ptr, word) -> word
  def zr_inflate_init2(strm, window_bits)
    if strm == 0
      return Z_STREAM_ERROR
    end
    ZStream[strm].msg = 0
    size = InflateState.size + (INF_LENS_WORDS * 4) + (INF_WORK_WORDS * 4) + (INF_ENOUGH * 4)
    st = Libc.malloc(size)
    if st == 0
      return Z_MEM_ERROR
    end
    Libc.memset(st, Machine.i32(0), size)
    ZStream[strm].state = st
    InflateState[st].strm = strm
    InflateState[st].window = 0
    InflateState[st].lens = st + InflateState.size
    InflateState[st].work = InflateState[st].lens + (INF_LENS_WORDS * 4)
    InflateState[st].codes = InflateState[st].work + (INF_WORK_WORDS * 4)
    InflateState[st].mode = INF_HEAD
    ret = zr_inflate_reset2(strm, window_bits)
    if ret != Z_OK
      Libc.free(st)
      ZStream[strm].state = 0
    end
    ret
  end

  # inflateEnd: frees the state and its window.
  #: (ptr) -> word
  def zr_inflate_end(strm)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    if InflateState[st].window != 0
      Libc.free(InflateState[st].window)
    end
    Libc.free(st)
    ZStream[strm].state = 0
    Z_OK
  end

  # fixedtables: the decoding tables of a fixed-code block.
  #: (ptr) -> void
  def zr_inflate_fixed_tables(st)
    InflateState[st].lencode = zr_inflate_lenfix()
    InflateState[st].lenbits = 9
    InflateState[st].distcode = zr_inflate_distfix()
    InflateState[st].distbits = 5
  end

  # updatewindow: copies the last wsize bytes of output before `end_`
  # into the sliding window. `copy` of them were written in this call.
  # The window is made on first use. Returns 1 when the window cannot be
  # made.
  #: (ptr, ptr, ptr, word) -> word
  def zr_inflate_update_window(strm, st, end_, copy)
    if InflateState[st].window == 0
      window = Libc.malloc(1 << InflateState[st].wbits)
      if window == 0
        return 1
      end
      InflateState[st].window = window
    end
    if InflateState[st].wsize == 0
      InflateState[st].wsize = 1 << InflateState[st].wbits
      InflateState[st].wnext = 0
      InflateState[st].whave = 0
    end
    wsize = InflateState[st].wsize
    wnext = InflateState[st].wnext
    window = InflateState[st].window
    if copy >= wsize
      Libc.memmove(window, end_ - wsize, wsize)
      InflateState[st].wnext = 0
      InflateState[st].whave = wsize
    else
      dist = wsize - wnext
      if dist > copy
        dist = copy
      end
      Libc.memmove(window + wnext, end_ - copy, dist)
      copy -= dist
      if copy != 0
        Libc.memmove(window, end_ - copy, copy)
        InflateState[st].wnext = copy
        InflateState[st].whave = wsize
      else
        wnext += dist
        if wnext == wsize
          wnext = 0
        end
        InflateState[st].wnext = wnext
        if InflateState[st].whave < wsize
          InflateState[st].whave = InflateState[st].whave + dist
        end
      end
    end
    0
  end

  # UPDATE_CHECK: the running check, a crc32 for a gzip wrapper and an
  # adler32 for a zlib wrapper.
  #: (ptr, word, ptr, word) -> word
  def zr_inflate_update_check(st, check, buf, len)
    if InflateState[st].flags != 0
      return zr_crc32(check, buf, len)
    end
    zr_adler32(check, buf, len)
  end

  # CRC2 and CRC4: adds the `n` low bytes of `word` to the header check.
  #: (ptr, word, word) -> void
  def zr_inflate_crc_header(st, word, n)
    hbuf = Machine.slot(8)
    Machine.store8(hbuf, 0, Machine.i8(word))
    Machine.store8(hbuf, 1, Machine.i8(word >> 8))
    Machine.store8(hbuf, 2, Machine.i8(word >> 16))
    Machine.store8(hbuf, 3, Machine.i8(word >> 24))
    InflateState[st].check = zr_crc32(InflateState[st].check, hbuf, n)
  end

  # Copies the registers of the stream from the cursor: RESTORE in the C.
  #: (ptr, ptr, ptr) -> void
  def zr_inf_restore(strm, st, cur)
    ZStream[strm].next_out = InfCursor[cur].put
    ZStream[strm].avail_out = InfCursor[cur].left
    ZStream[strm].next_in = InfCursor[cur].nxt
    ZStream[strm].avail_in = InfCursor[cur].have
    InflateState[st].hold = InfCursor[cur].hold
    InflateState[st].bits = InfCursor[cur].bits
  end

  # Loads the cursor from the registers of the stream: LOAD in the C.
  #: (ptr, ptr, ptr) -> void
  def zr_inf_load(strm, st, cur)
    InfCursor[cur].put = ZStream[strm].next_out
    InfCursor[cur].left = ZStream[strm].avail_out
    InfCursor[cur].nxt = ZStream[strm].next_in
    InfCursor[cur].have = ZStream[strm].avail_in
    InfCursor[cur].hold = InflateState[st].hold
    InfCursor[cur].bits = InflateState[st].bits
  end

  # PULLBYTE: adds one input byte to the bit buffer. Returns false when
  # there is no input, and then inflate leaves.
  #: (ptr) -> bool
  def zr_inf_pull(cur)
    have = InfCursor[cur].have
    if have == 0
      return false
    end
    InfCursor[cur].have = have - 1
    nxt = InfCursor[cur].nxt
    InfCursor[cur].hold = InfCursor[cur].hold + (Machine.ptr(zr_zlib_byte(nxt)) << InfCursor[cur].bits)
    InfCursor[cur].nxt = nxt + 1
    InfCursor[cur].bits = InfCursor[cur].bits + 8
    true
  end

  # NEEDBITS: gets at least `n` bits into the buffer. Returns false when
  # the input ends first.
  #: (ptr, word) -> bool
  def zr_inf_need(cur, n)
    while InfCursor[cur].bits < n
      if !zr_inf_pull(cur)
        return false
      end
    end
    true
  end

  # BITS: the low `n` bits of the buffer.
  #: (ptr, word) -> word
  def zr_inf_bits(cur, n)
    Machine.word(InfCursor[cur].hold & ((1 << n) - 1))
  end

  # DROPBITS
  #: (ptr, word) -> void
  def zr_inf_drop(cur, n)
    InfCursor[cur].hold = InfCursor[cur].hold >> n
    InfCursor[cur].bits = InfCursor[cur].bits - n
  end

  # INITBITS
  #: (ptr) -> void
  def zr_inf_init_bits(cur)
    InfCursor[cur].hold = 0
    InfCursor[cur].bits = 0
  end

  # BYTEBITS: moves the buffer to a byte boundary.
  #: (ptr) -> void
  def zr_inf_byte_bits(cur)
    n = InfCursor[cur].bits & 7
    InfCursor[cur].hold = InfCursor[cur].hold >> n
    InfCursor[cur].bits = InfCursor[cur].bits - n
  end

  # A data error: sets its message on the stream, and sets the BAD mode.
  #: (ptr, ptr, ptr) -> word
  def zr_inf_bad(strm, st, msg)
    ZStream[strm].msg = msg
    InflateState[st].mode = INF_BAD
    INF_NEXT
  end

  # The HEAD mode: no wrapper, the first two bytes of a gzip header, or a
  # zlib header.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_head(strm, st, cur)
    if InflateState[st].wrap == 0
      InflateState[st].mode = INF_TYPEDO
      return INF_NEXT
    end
    if !zr_inf_need(cur, 16)
      return INF_LEAVE
    end
    hold = Machine.word(InfCursor[cur].hold)
    if (InflateState[st].wrap & 2) != 0 && hold == 35615
      if InflateState[st].wbits == 0
        InflateState[st].wbits = 15
      end
      InflateState[st].check = 0
      zr_inflate_crc_header(st, hold, 2)
      zr_inf_init_bits(cur)
      InflateState[st].mode = INF_FLAGS
      return INF_NEXT
    end
    if (InflateState[st].wrap & 1) == 0 || ((zr_inf_bits(cur, 8) << 8) + (hold >> 8)) % 31 != 0
      return zr_inf_bad(strm, st, Machine.bytes("incorrect header check\0"))
    end
    if zr_inf_bits(cur, 4) != Z_DEFLATED
      return zr_inf_bad(strm, st, Machine.bytes("unknown compression method\0"))
    end
    zr_inf_drop(cur, 4)
    len = zr_inf_bits(cur, 4) + 8
    if InflateState[st].wbits == 0
      InflateState[st].wbits = len
    end
    if len > 15 || len > InflateState[st].wbits
      return zr_inf_bad(strm, st, Machine.bytes("invalid window size\0"))
    end
    InflateState[st].dmax = 1 << len
    InflateState[st].flags = 0
    InflateState[st].check = 1
    ZStream[strm].adler = 1
    if (Machine.word(InfCursor[cur].hold) & 512) != 0
      InflateState[st].mode = INF_DICTID
    else
      InflateState[st].mode = INF_TYPE
    end
    zr_inf_init_bits(cur)
    INF_NEXT
  end

  # The FLAGS through HCRC modes: reads a gzip header and checks it when
  # the header has a check. No header struct gets the fields.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_gzip_header(strm, st, cur)
    mode = InflateState[st].mode
    if mode == INF_FLAGS
      if !zr_inf_need(cur, 16)
        return INF_LEAVE
      end
      flags = Machine.word(InfCursor[cur].hold)
      InflateState[st].flags = flags
      if (flags & 255) != Z_DEFLATED
        return zr_inf_bad(strm, st, Machine.bytes("unknown compression method\0"))
      end
      if (flags & 57344) != 0
        return zr_inf_bad(strm, st, Machine.bytes("unknown header flags set\0"))
      end
      if (flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
        zr_inflate_crc_header(st, flags, 2)
      end
      zr_inf_init_bits(cur)
      mode = INF_TIME
      InflateState[st].mode = mode
    end
    if mode == INF_TIME
      if !zr_inf_need(cur, 32)
        return INF_LEAVE
      end
      if (InflateState[st].flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
        zr_inflate_crc_header(st, Machine.word(InfCursor[cur].hold), 4)
      end
      zr_inf_init_bits(cur)
      mode = INF_OS
      InflateState[st].mode = mode
    end
    if mode == INF_OS
      if !zr_inf_need(cur, 16)
        return INF_LEAVE
      end
      if (InflateState[st].flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
        zr_inflate_crc_header(st, Machine.word(InfCursor[cur].hold), 2)
      end
      zr_inf_init_bits(cur)
      mode = INF_EXLEN
      InflateState[st].mode = mode
    end
    if mode == INF_EXLEN
      if (InflateState[st].flags & 1024) != 0
        if !zr_inf_need(cur, 16)
          return INF_LEAVE
        end
        InflateState[st].length = Machine.word(InfCursor[cur].hold)
        if (InflateState[st].flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
          zr_inflate_crc_header(st, Machine.word(InfCursor[cur].hold), 2)
        end
        zr_inf_init_bits(cur)
      end
      mode = INF_EXTRA
      InflateState[st].mode = mode
    end
    if mode == INF_EXTRA
      if (InflateState[st].flags & 1024) != 0
        copy = InflateState[st].length
        if copy > InfCursor[cur].have
          copy = InfCursor[cur].have
        end
        if copy != 0
          if (InflateState[st].flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
            InflateState[st].check = zr_crc32(InflateState[st].check, InfCursor[cur].nxt, copy)
          end
          InfCursor[cur].have = InfCursor[cur].have - copy
          InfCursor[cur].nxt = InfCursor[cur].nxt + copy
          InflateState[st].length = InflateState[st].length - copy
        end
        if InflateState[st].length != 0
          return INF_LEAVE
        end
      end
      InflateState[st].length = 0
      mode = INF_NAME
      InflateState[st].mode = mode
    end
    if mode == INF_NAME
      if (InflateState[st].flags & 2048) != 0
        if !zr_inflate_skip_string(st, cur)
          return INF_LEAVE
        end
      end
      InflateState[st].length = 0
      mode = INF_COMMENT
      InflateState[st].mode = mode
    end
    if mode == INF_COMMENT
      if (InflateState[st].flags & 4096) != 0
        if !zr_inflate_skip_string(st, cur)
          return INF_LEAVE
        end
      end
      mode = INF_HCRC
      InflateState[st].mode = mode
    end
    if (InflateState[st].flags & 512) != 0
      if !zr_inf_need(cur, 16)
        return INF_LEAVE
      end
      if (InflateState[st].wrap & 4) != 0 && Machine.word(InfCursor[cur].hold) != (InflateState[st].check & 65535)
        return zr_inf_bad(strm, st, Machine.bytes("header crc mismatch\0"))
      end
      zr_inf_init_bits(cur)
    end
    InflateState[st].check = 0
    ZStream[strm].adler = 0
    InflateState[st].mode = INF_TYPE
    INF_NEXT
  end

  # The work of the NAME and COMMENT modes: skips a zero-terminated header
  # string, and adds it to the check when the header has a check. Returns
  # false when the input ends before the string.
  #: (ptr, ptr) -> bool
  def zr_inflate_skip_string(st, cur)
    have = InfCursor[cur].have
    if have == 0
      return false
    end
    nxt = InfCursor[cur].nxt
    copy = 0
    len = 0
    while true
      len = zr_zlib_byte(nxt + copy)
      copy += 1
      if len == 0 || copy >= have
        break
      end
    end
    if (InflateState[st].flags & 512) != 0 && (InflateState[st].wrap & 4) != 0
      InflateState[st].check = zr_crc32(InflateState[st].check, nxt, copy)
    end
    InfCursor[cur].have = have - copy
    InfCursor[cur].nxt = nxt + copy
    len == 0
  end

  # The DICTID and DICT modes: reads the check of the dictionary, and
  # tells the caller to set the dictionary when it has not.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_dict(strm, st, cur)
    if InflateState[st].mode == INF_DICTID
      if !zr_inf_need(cur, 32)
        return INF_LEAVE
      end
      check = zr_zlib_swap32(Machine.word(InfCursor[cur].hold))
      InflateState[st].check = check
      ZStream[strm].adler = check
      zr_inf_init_bits(cur)
      InflateState[st].mode = INF_DICT
    end
    if InflateState[st].havedict == 0
      zr_inf_restore(strm, st, cur)
      InfCursor[cur].ret = Z_NEED_DICT
      return INF_RETURN
    end
    InflateState[st].check = 1
    ZStream[strm].adler = 1
    InflateState[st].mode = INF_TYPE
    INF_NEXT
  end

  # The TYPE, TYPEDO, STORED, COPY_ and COPY modes: the header of a block,
  # and the bytes of a stored block.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_type(strm, st, cur)
    mode = InflateState[st].mode
    flush = InfCursor[cur].flush
    if mode == INF_TYPE
      if flush == Z_BLOCK || flush == Z_TREES
        return INF_LEAVE
      end
      mode = INF_TYPEDO
    end
    if mode == INF_TYPEDO
      if InflateState[st].last != 0
        zr_inf_byte_bits(cur)
        InflateState[st].mode = INF_CHECK
        return INF_NEXT
      end
      if !zr_inf_need(cur, 3)
        return INF_LEAVE
      end
      InflateState[st].last = zr_inf_bits(cur, 1)
      zr_inf_drop(cur, 1)
      kind = zr_inf_bits(cur, 2)
      if kind == 0
        InflateState[st].mode = INF_STORED
      elsif kind == 1
        zr_inflate_fixed_tables(st)
        InflateState[st].mode = INF_LEN_
        if flush == Z_TREES
          zr_inf_drop(cur, 2)
          return INF_LEAVE
        end
      elsif kind == 2
        InflateState[st].mode = INF_TABLE
      else
        ZStream[strm].msg = Machine.bytes("invalid block type\0")
        InflateState[st].mode = INF_BAD
      end
      zr_inf_drop(cur, 2)
      return INF_NEXT
    end
    if mode == INF_STORED
      zr_inf_byte_bits(cur)
      if !zr_inf_need(cur, 32)
        return INF_LEAVE
      end
      hold = Machine.word(InfCursor[cur].hold)
      if (hold & 65535) != ((hold >> 16) ^ 65535)
        return zr_inf_bad(strm, st, Machine.bytes("invalid stored block lengths\0"))
      end
      InflateState[st].length = hold & 65535
      zr_inf_init_bits(cur)
      mode = INF_COPY_
      InflateState[st].mode = mode
      if flush == Z_TREES
        return INF_LEAVE
      end
    end
    if mode == INF_COPY_
      mode = INF_COPY
      InflateState[st].mode = mode
    end
    copy = InflateState[st].length
    if copy != 0
      if copy > InfCursor[cur].have
        copy = InfCursor[cur].have
      end
      if copy > InfCursor[cur].left
        copy = InfCursor[cur].left
      end
      if copy == 0
        return INF_LEAVE
      end
      Libc.memmove(InfCursor[cur].put, InfCursor[cur].nxt, copy)
      InfCursor[cur].have = InfCursor[cur].have - copy
      InfCursor[cur].nxt = InfCursor[cur].nxt + copy
      InfCursor[cur].left = InfCursor[cur].left - copy
      InfCursor[cur].put = InfCursor[cur].put + copy
      InflateState[st].length = InflateState[st].length - copy
      return INF_NEXT
    end
    InflateState[st].mode = INF_TYPE
    INF_NEXT
  end

  # Builds a table. The table pointer and root bits go to inflate_table
  # through stack slots, and come back through them.
  #: (ptr, word, word, word) -> word
  def zr_inflate_build(st, type, codes, root)
    table = Machine.slot(8)
    bits = Machine.slot(8)
    Machine.store64(table, 0, Machine.word(InflateState[st].nxt))
    Machine.store64(bits, 0, root)
    lens = InflateState[st].lens
    if type == INF_DISTS
      lens += InflateState[st].nlen * 4
    end
    ret = zr_inflate_table(type, lens, codes, table, bits, InflateState[st].work)
    InflateState[st].nxt = Machine.ptr(Machine.load64(table, 0))
    if type == INF_DISTS
      InflateState[st].distbits = Machine.load64(bits, 0)
    else
      InflateState[st].lenbits = Machine.load64(bits, 0)
    end
    ret
  end

  # Gets a code from `table` for the low bits of the buffer. It pulls
  # input until all the bits of the code are there. Returns the code, or
  # -1 when the input ends.
  #: (ptr, ptr, word) -> word
  def zr_inflate_decode(cur, table, table_bits)
    while true
      here = zr_zlib_u32(table, zr_inf_bits(cur, table_bits))
      if zr_inf_code_bits(here) <= InfCursor[cur].bits
        return here
      end
      if !zr_inf_pull(cur)
        return 0 - 1
      end
    end
    0
  end

  # Gets the second-level code under `last`, and pulls input as needed.
  # Returns the code, or -1 when the input ends.
  #: (ptr, ptr, word) -> word
  def zr_inflate_decode_under(cur, table, last)
    while true
      here = zr_zlib_u32(table, zr_inf_code_val(last) + (zr_inf_bits(cur, zr_inf_code_bits(last) + zr_inf_code_op(last)) >> zr_inf_code_bits(last)))
      if zr_inf_code_bits(last) + zr_inf_code_bits(here) <= InfCursor[cur].bits
        return here
      end
      if !zr_inf_pull(cur)
        return 0 - 1
      end
    end
    0
  end

  # The TABLE, LENLENS and CODELENS modes: reads the code lengths of a
  # dynamic block and builds its tables.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_table_lens(strm, st, cur)
    mode = InflateState[st].mode
    lens = InflateState[st].lens
    if mode == INF_TABLE
      if !zr_inf_need(cur, 14)
        return INF_LEAVE
      end
      InflateState[st].nlen = zr_inf_bits(cur, 5) + 257
      zr_inf_drop(cur, 5)
      InflateState[st].ndist = zr_inf_bits(cur, 5) + 1
      zr_inf_drop(cur, 5)
      InflateState[st].ncode = zr_inf_bits(cur, 4) + 4
      zr_inf_drop(cur, 4)
      if InflateState[st].nlen > 286 || InflateState[st].ndist > 30
        return zr_inf_bad(strm, st, Machine.bytes("too many length or distance symbols\0"))
      end
      InflateState[st].have = 0
      mode = INF_LENLENS
      InflateState[st].mode = mode
    end
    if mode == INF_LENLENS
      order = zr_inflate_order()
      while InflateState[st].have < InflateState[st].ncode
        if !zr_inf_need(cur, 3)
          return INF_LEAVE
        end
        zr_zlib_set_u32(lens, zr_zlib_u32(order, InflateState[st].have), zr_inf_bits(cur, 3))
        InflateState[st].have = InflateState[st].have + 1
        zr_inf_drop(cur, 3)
      end
      while InflateState[st].have < 19
        zr_zlib_set_u32(lens, zr_zlib_u32(order, InflateState[st].have), 0)
        InflateState[st].have = InflateState[st].have + 1
      end
      InflateState[st].nxt = InflateState[st].codes
      InflateState[st].lencode = InflateState[st].codes
      if zr_inflate_build(st, INF_CODES, 19, 7) != 0
        return zr_inf_bad(strm, st, Machine.bytes("invalid code lengths set\0"))
      end
      InflateState[st].have = 0
      mode = INF_CODELENS
      InflateState[st].mode = mode
    end
    total = InflateState[st].nlen + InflateState[st].ndist
    while InflateState[st].have < total
      here = zr_inflate_decode(cur, InflateState[st].lencode, InflateState[st].lenbits)
      if here < 0
        return INF_LEAVE
      end
      val = zr_inf_code_val(here)
      here_bits = zr_inf_code_bits(here)
      if val < 16
        zr_inf_drop(cur, here_bits)
        zr_zlib_set_u32(lens, InflateState[st].have, val)
        InflateState[st].have = InflateState[st].have + 1
      else
        len = 0
        copy = 0
        if val == 16
          if !zr_inf_need(cur, here_bits + 2)
            return INF_LEAVE
          end
          zr_inf_drop(cur, here_bits)
          if InflateState[st].have == 0
            return zr_inf_bad(strm, st, Machine.bytes("invalid bit length repeat\0"))
          end
          len = zr_zlib_u32(lens, InflateState[st].have - 1)
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
        if InflateState[st].have + copy > total
          return zr_inf_bad(strm, st, Machine.bytes("invalid bit length repeat\0"))
        end
        while copy > 0
          zr_zlib_set_u32(lens, InflateState[st].have, len)
          InflateState[st].have = InflateState[st].have + 1
          copy -= 1
        end
      end
    end
    if zr_zlib_u32(lens, 256) == 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid code -- missing end-of-block\0"))
    end
    InflateState[st].nxt = InflateState[st].codes
    InflateState[st].lencode = InflateState[st].codes
    if zr_inflate_build(st, INF_LENS, InflateState[st].nlen, 9) != 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid literal/lengths set\0"))
    end
    InflateState[st].distcode = InflateState[st].nxt
    if zr_inflate_build(st, INF_DISTS, InflateState[st].ndist, 6) != 0
      return zr_inf_bad(strm, st, Machine.bytes("invalid distances set\0"))
    end
    InflateState[st].mode = INF_LEN_
    if InfCursor[cur].flush == Z_TREES
      return INF_LEAVE
    end
    INF_NEXT
  end

  # The LEN_ through LIT modes: decodes literals and matches one at a
  # time, or through inflate_fast while the buffers are large enough.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_codes(strm, st, cur)
    mode = InflateState[st].mode
    if mode == INF_LEN_
      mode = INF_LEN
      InflateState[st].mode = mode
    end
    if mode == INF_LEN
      if InfCursor[cur].have >= 6 && InfCursor[cur].left >= 258
        zr_inf_restore(strm, st, cur)
        zr_inflate_fast(strm, InfCursor[cur].out)
        zr_inf_load(strm, st, cur)
        if InflateState[st].mode == INF_TYPE
          InflateState[st].back = 0 - 1
        end
        return INF_NEXT
      end
      InflateState[st].back = 0
      here = zr_inflate_decode(cur, InflateState[st].lencode, InflateState[st].lenbits)
      if here < 0
        return INF_LEAVE
      end
      if zr_inf_code_op(here) != 0 && (zr_inf_code_op(here) & 240) == 0
        last = here
        here = zr_inflate_decode_under(cur, InflateState[st].lencode, last)
        if here < 0
          return INF_LEAVE
        end
        zr_inf_drop(cur, zr_inf_code_bits(last))
        InflateState[st].back = InflateState[st].back + zr_inf_code_bits(last)
      end
      zr_inf_drop(cur, zr_inf_code_bits(here))
      InflateState[st].back = InflateState[st].back + zr_inf_code_bits(here)
      InflateState[st].length = zr_inf_code_val(here)
      op = zr_inf_code_op(here)
      if op == 0
        InflateState[st].mode = INF_LIT
        return INF_NEXT
      end
      if (op & 32) != 0
        InflateState[st].back = 0 - 1
        InflateState[st].mode = INF_TYPE
        return INF_NEXT
      end
      if (op & 64) != 0
        return zr_inf_bad(strm, st, Machine.bytes("invalid literal/length code\0"))
      end
      InflateState[st].extra = op & 15
      mode = INF_LENEXT
      InflateState[st].mode = mode
    end
    if mode == INF_LENEXT
      extra = InflateState[st].extra
      if extra != 0
        if !zr_inf_need(cur, extra)
          return INF_LEAVE
        end
        InflateState[st].length = InflateState[st].length + zr_inf_bits(cur, extra)
        zr_inf_drop(cur, extra)
        InflateState[st].back = InflateState[st].back + extra
      end
      InflateState[st].was = InflateState[st].length
      mode = INF_DIST
      InflateState[st].mode = mode
    end
    if mode == INF_DIST
      here = zr_inflate_decode(cur, InflateState[st].distcode, InflateState[st].distbits)
      if here < 0
        return INF_LEAVE
      end
      if (zr_inf_code_op(here) & 240) == 0
        last = here
        here = zr_inflate_decode_under(cur, InflateState[st].distcode, last)
        if here < 0
          return INF_LEAVE
        end
        zr_inf_drop(cur, zr_inf_code_bits(last))
        InflateState[st].back = InflateState[st].back + zr_inf_code_bits(last)
      end
      zr_inf_drop(cur, zr_inf_code_bits(here))
      InflateState[st].back = InflateState[st].back + zr_inf_code_bits(here)
      if (zr_inf_code_op(here) & 64) != 0
        return zr_inf_bad(strm, st, Machine.bytes("invalid distance code\0"))
      end
      InflateState[st].offset = zr_inf_code_val(here)
      InflateState[st].extra = zr_inf_code_op(here) & 15
      mode = INF_DISTEXT
      InflateState[st].mode = mode
    end
    if mode == INF_DISTEXT
      extra = InflateState[st].extra
      if extra != 0
        if !zr_inf_need(cur, extra)
          return INF_LEAVE
        end
        InflateState[st].offset = InflateState[st].offset + zr_inf_bits(cur, extra)
        zr_inf_drop(cur, extra)
        InflateState[st].back = InflateState[st].back + extra
      end
      mode = INF_MATCH
      InflateState[st].mode = mode
    end
    if mode == INF_MATCH
      left = InfCursor[cur].left
      if left == 0
        return INF_LEAVE
      end
      put = InfCursor[cur].put
      copy = InfCursor[cur].out - left
      from = put
      if InflateState[st].offset > copy
        copy = InflateState[st].offset - copy
        if copy > InflateState[st].whave
          if InflateState[st].sane != 0
            return zr_inf_bad(strm, st, Machine.bytes("invalid distance too far back\0"))
          end
        end
        if copy > InflateState[st].wnext
          copy -= InflateState[st].wnext
          from = InflateState[st].window + (InflateState[st].wsize - copy)
        else
          from = InflateState[st].window + (InflateState[st].wnext - copy)
        end
        if copy > InflateState[st].length
          copy = InflateState[st].length
        end
      else
        from = put - InflateState[st].offset
        copy = InflateState[st].length
      end
      if copy > left
        copy = left
      end
      InfCursor[cur].left = left - copy
      InflateState[st].length = InflateState[st].length - copy
      zr_zlib_copy_bytes(put, from, copy)
      InfCursor[cur].put = put + copy
      if InflateState[st].length == 0
        InflateState[st].mode = INF_LEN
      end
      return INF_NEXT
    end
    if InfCursor[cur].left == 0
      return INF_LEAVE
    end
    Machine.store8(InfCursor[cur].put, 0, Machine.i8(InflateState[st].length))
    InfCursor[cur].put = InfCursor[cur].put + 1
    InfCursor[cur].left = InfCursor[cur].left - 1
    InflateState[st].mode = INF_LEN
    INF_NEXT
  end

  # The CHECK, LENGTH, DONE, BAD, MEM and SYNC modes: the trailer, and
  # the end states.
  #: (ptr, ptr, ptr) -> word
  def zr_inflate_check(strm, st, cur)
    mode = InflateState[st].mode
    if mode == INF_CHECK
      if InflateState[st].wrap != 0
        if !zr_inf_need(cur, 32)
          return INF_LEAVE
        end
        out = InfCursor[cur].out - InfCursor[cur].left
        ZStream[strm].total_out = ZStream[strm].total_out + out
        InflateState[st].total = InflateState[st].total + out
        if (InflateState[st].wrap & 4) != 0 && out != 0
          check = zr_inflate_update_check(st, InflateState[st].check, InfCursor[cur].put - out, out)
          InflateState[st].check = check
          ZStream[strm].adler = check
        end
        InfCursor[cur].out = InfCursor[cur].left
        hold = Machine.word(InfCursor[cur].hold)
        if InflateState[st].flags == 0
          hold = zr_zlib_swap32(hold)
        end
        if (InflateState[st].wrap & 4) != 0 && hold != InflateState[st].check
          return zr_inf_bad(strm, st, Machine.bytes("incorrect data check\0"))
        end
        zr_inf_init_bits(cur)
      end
      mode = INF_LENGTH
      InflateState[st].mode = mode
    end
    if mode == INF_LENGTH
      if InflateState[st].wrap != 0 && InflateState[st].flags != 0
        if !zr_inf_need(cur, 32)
          return INF_LEAVE
        end
        if (InflateState[st].wrap & 4) != 0 && Machine.word(InfCursor[cur].hold) != (InflateState[st].total & ZLIB_MASK32)
          return zr_inf_bad(strm, st, Machine.bytes("incorrect length check\0"))
        end
        zr_inf_init_bits(cur)
      end
      mode = INF_DONE
      InflateState[st].mode = mode
    end
    if mode == INF_DONE
      InfCursor[cur].ret = Z_STREAM_END
      return INF_LEAVE
    end
    if mode == INF_BAD
      InfCursor[cur].ret = Z_DATA_ERROR
      return INF_LEAVE
    end
    if mode == INF_MEM
      InfCursor[cur].ret = Z_MEM_ERROR
      return INF_RETURN
    end
    InfCursor[cur].ret = Z_STREAM_ERROR
    INF_RETURN
  end

  # inflate: decompresses as much of the stream as the input and output
  # space allow.
  #: (ptr, word) -> word
  def zr_inflate(strm, flush)
    if zr_inflate_state_check(strm) != 0 || ZStream[strm].next_out == 0 || (ZStream[strm].next_in == 0 && ZStream[strm].avail_in != 0)
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    if InflateState[st].mode == INF_TYPE
      InflateState[st].mode = INF_TYPEDO
    end
    cur = Machine.slot(InfCursor.size)
    zr_inf_load(strm, st, cur)
    InfCursor[cur].in = InfCursor[cur].have
    InfCursor[cur].out = InfCursor[cur].left
    InfCursor[cur].flush = flush
    InfCursor[cur].ret = Z_OK
    step = INF_NEXT
    while step == INF_NEXT
      mode = InflateState[st].mode
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
      return InfCursor[cur].ret
    end
    zr_inf_restore(strm, st, cur)
    out = InfCursor[cur].out
    mode = InflateState[st].mode
    if InflateState[st].wsize != 0 || (out != ZStream[strm].avail_out && mode < INF_BAD && (mode < INF_CHECK || flush != Z_FINISH))
      if zr_inflate_update_window(strm, st, ZStream[strm].next_out, out - ZStream[strm].avail_out) != 0
        InflateState[st].mode = INF_MEM
        return Z_MEM_ERROR
      end
    end
    in_ = InfCursor[cur].in - ZStream[strm].avail_in
    out -= ZStream[strm].avail_out
    ZStream[strm].total_in = ZStream[strm].total_in + in_
    ZStream[strm].total_out = ZStream[strm].total_out + out
    InflateState[st].total = InflateState[st].total + out
    if (InflateState[st].wrap & 4) != 0 && out != 0
      check = zr_inflate_update_check(st, InflateState[st].check, ZStream[strm].next_out - out, out)
      InflateState[st].check = check
      ZStream[strm].adler = check
    end
    data_type = InflateState[st].bits
    if InflateState[st].last != 0
      data_type += 64
    end
    if mode == INF_TYPE
      data_type += 128
    end
    if mode == INF_LEN_ || mode == INF_COPY_
      data_type += 256
    end
    ZStream[strm].data_type = data_type
    ret = InfCursor[cur].ret
    if ((in_ == 0 && out == 0) || flush == Z_FINISH) && ret == Z_OK
      ret = Z_BUF_ERROR
    end
    ret
  end

  # inflateSetDictionary: puts into the window the dictionary that a zlib
  # stream identifies, or any dictionary for a raw stream.
  #: (ptr, ptr, word) -> word
  def zr_inflate_set_dictionary(strm, dictionary, length)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    if InflateState[st].wrap != 0 && InflateState[st].mode != INF_DICT
      return Z_STREAM_ERROR
    end
    if InflateState[st].mode == INF_DICT
      if zr_adler32(1, dictionary, length) != InflateState[st].check
        return Z_DATA_ERROR
      end
    end
    if zr_inflate_update_window(strm, st, dictionary + length, length) != 0
      InflateState[st].mode = INF_MEM
      return Z_MEM_ERROR
    end
    InflateState[st].havedict = 1
    Z_OK
  end

  # syncsearch: searches `len` bytes at `buf` for 0, 0, 0xff, 0xff. The
  # word at `have` contains the count found so far. Returns the number of
  # bytes read.
  #: (ptr, ptr, word) -> word
  def zr_inflate_sync_search(have, buf, len)
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

  # inflateSync: searches the input for the next full flush point, and
  # sets the stream to continue from there.
  #: (ptr) -> word
  def zr_inflate_sync(strm)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    if ZStream[strm].avail_in == 0 && InflateState[st].bits < 8
      return Z_BUF_ERROR
    end
    have = Machine.slot(8)
    if InflateState[st].mode != INF_SYNC
      InflateState[st].mode = INF_SYNC
      n = InflateState[st].bits & 7
      InflateState[st].hold = InflateState[st].hold >> n
      InflateState[st].bits = InflateState[st].bits - n
      buf = Machine.slot(8)
      len = 0
      while InflateState[st].bits >= 8
        Machine.store8(buf + len, 0, Machine.i8(Machine.word(InflateState[st].hold)))
        len += 1
        InflateState[st].hold = InflateState[st].hold >> 8
        InflateState[st].bits = InflateState[st].bits - 8
      end
      InflateState[st].have = 0
      Machine.store64(have, 0, 0)
      zr_inflate_sync_search(have, buf, len)
      InflateState[st].have = Machine.load64(have, 0)
    end
    Machine.store64(have, 0, InflateState[st].have)
    len = zr_inflate_sync_search(have, ZStream[strm].next_in, ZStream[strm].avail_in)
    InflateState[st].have = Machine.load64(have, 0)
    ZStream[strm].avail_in = ZStream[strm].avail_in - len
    ZStream[strm].next_in = ZStream[strm].next_in + len
    ZStream[strm].total_in = ZStream[strm].total_in + len
    if InflateState[st].have != 4
      return Z_DATA_ERROR
    end
    if InflateState[st].flags == 0 - 1
      InflateState[st].wrap = 0
    else
      InflateState[st].wrap = InflateState[st].wrap & 3
    end
    flags = InflateState[st].flags
    in_ = ZStream[strm].total_in
    out = ZStream[strm].total_out
    zr_inflate_reset(strm)
    ZStream[strm].total_in = in_
    ZStream[strm].total_out = out
    InflateState[st].flags = flags
    InflateState[st].mode = INF_TYPE
    Z_OK
  end

  # inflateSyncPoint: whether the stream is at the end of a block that a
  # sync or full flush wrote.
  #: (ptr) -> word
  def zr_inflate_sync_point(strm)
    if zr_inflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    st = ZStream[strm].state
    if InflateState[st].mode == INF_STORED && InflateState[st].bits == 0
      return 1
    end
    0
  end
end
