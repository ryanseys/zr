module Zr::Kern
  # deflate.c: the compressor. The state is the C deflate_state, with its
  # trees, counts, heap and depths in one block after it. The four buffers
  # that the C code allocates separately are also separate here. Nothing
  # calls deflateSetHeader, so no gzip header struct is set, and a gzip
  # stream gets the plain ten-byte header.
  # Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.
  class DeflateState < Layout
    attr_accessor :strm #: ptr
    attr_accessor :status #: word
    attr_accessor :pending_buf #: ptr
    attr_accessor :pending_buf_size #: word
    attr_accessor :pending_out #: ptr
    attr_accessor :pending #: word
    attr_accessor :wrap #: word
    attr_accessor :last_flush #: word
    attr_accessor :w_size #: word
    attr_accessor :w_bits #: word
    attr_accessor :w_mask #: word
    attr_accessor :window #: ptr
    attr_accessor :window_size #: word
    attr_accessor :prev #: ptr
    attr_accessor :head #: ptr
    attr_accessor :ins_h #: word
    attr_accessor :hash_size #: word
    attr_accessor :hash_bits #: word
    attr_accessor :hash_mask #: word
    attr_accessor :hash_shift #: word
    attr_accessor :block_start #: word
    attr_accessor :match_length #: word
    attr_accessor :prev_match #: word
    attr_accessor :match_available #: word
    attr_accessor :strstart #: word
    attr_accessor :match_start #: word
    attr_accessor :lookahead #: word
    attr_accessor :prev_length #: word
    attr_accessor :max_chain_length #: word
    attr_accessor :max_lazy_match #: word
    attr_accessor :level #: word
    attr_accessor :strategy #: word
    attr_accessor :good_match #: word
    attr_accessor :nice_match #: word
    attr_accessor :dyn_ltree #: ptr
    attr_accessor :dyn_dtree #: ptr
    attr_accessor :bl_tree #: ptr
    attr_accessor :l_max_code #: word
    attr_accessor :d_max_code #: word
    attr_accessor :bl_max_code #: word
    attr_accessor :bl_count #: ptr
    attr_accessor :heap #: ptr
    attr_accessor :heap_len #: word
    attr_accessor :heap_max #: word
    attr_accessor :depth #: ptr
    attr_accessor :sym_buf #: ptr
    attr_accessor :lit_bufsize #: word
    attr_accessor :sym_next #: word
    attr_accessor :sym_end #: word
    attr_accessor :opt_len #: word
    attr_accessor :static_len #: word
    attr_accessor :matches #: word
    attr_accessor :insert #: word
    attr_accessor :bi_buf #: word
    attr_accessor :bi_valid #: word
    attr_accessor :high_water #: word
  end

  # The stream's status.
  DEF_INIT_STATE = 42
  DEF_GZIP_STATE = 57
  DEF_EXTRA_STATE = 69
  DEF_NAME_STATE = 73
  DEF_COMMENT_STATE = 91
  DEF_HCRC_STATE = 103
  DEF_BUSY_STATE = 113
  DEF_FINISH_STATE = 666

  # The values that a block function returns.
  DEF_NEED_MORE = 0
  DEF_BLOCK_DONE = 1
  DEF_FINISH_STARTED = 2
  DEF_FINISH_DONE = 3

  # The kinds of block function in the configuration table.
  DEF_KIND_STORED = 0
  DEF_KIND_FAST = 1
  DEF_KIND_SLOW = 2

  DEF_TOO_FAR = 4096
  DEF_MIN_LOOKAHEAD = 262
  DEF_WIN_INIT = 258
  DEF_MAX_STORED = 65535
  DEF_MAX_MEM_LEVEL = 9
  DEF_PRESET_DICT = 32
  DEF_NIL = 0
  Z_DEFAULT_COMPRESSION = 0 - 1
  Z_FILTERED = 1
  Z_HUFFMAN_ONLY = 2
  Z_RLE = 3
  Z_FIXED = 4

  # The block after the struct that contains the trees, counts, heap and
  # depths.
  DEF_LTREE_BYTES = 4584
  DEF_DTREE_BYTES = 488
  DEF_BLTREE_BYTES = 312
  DEF_BL_COUNT_BYTES = 64
  DEF_HEAP_BYTES = 2292
  DEF_DEPTH_BYTES = 576
  DEF_TAIL_BYTES = 8316

  # Returns column `col` of the configuration table (0 good, 1 lazy,
  # 2 nice, 3 chain) for `level`.
  #: (word, word) -> word
  def zr_deflate_config(level, col)
    zr_zlib_u32(zr_deflate_config_table(), (level * 4) + col)
  end

  # The func column of the configuration table: the block function that a
  # level runs.
  #: (word) -> word
  def zr_deflate_kind(level)
    if level == 0
      return DEF_KIND_STORED
    elsif level <= 3
      return DEF_KIND_FAST
    end
    DEF_KIND_SLOW
  end

  # MAX_DIST
  #: (ptr) -> word
  def zr_deflate_max_dist(s)
    DeflateState[s].w_size - DEF_MIN_LOOKAHEAD
  end

  # RANK: puts Z_BLOCK between Z_NO_FLUSH and Z_PARTIAL_FLUSH.
  #: (word) -> word
  def zr_deflate_rank(f)
    if f > 4
      return (f * 2) - 9
    end
    f * 2
  end

  # UPDATE_HASH: returns the hash `h` updated with the byte `c`.
  #: (ptr, word, word) -> word
  def zr_deflate_hash(s, h, c)
    ((h << DeflateState[s].hash_shift) ^ c) & DeflateState[s].hash_mask
  end

  #: (ptr, word) -> word
  def zr_deflate_window_byte(s, i)
    zr_zlib_byte(DeflateState[s].window + i)
  end

  # INSERT_STRING: inserts the string at `str` into the hash chains.
  # Returns the previous head of its hash chain.
  #: (ptr, word) -> word
  def zr_deflate_insert_string(s, str)
    ins_h = zr_deflate_hash(s, DeflateState[s].ins_h, zr_deflate_window_byte(s, str + MIN_MATCH - 1))
    DeflateState[s].ins_h = ins_h
    match_head = zr_zlib_u32(DeflateState[s].head, ins_h)
    zr_zlib_set_u32(DeflateState[s].prev, str & DeflateState[s].w_mask, match_head)
    zr_zlib_set_u32(DeflateState[s].head, ins_h, str)
    match_head
  end

  # CLEAR_HASH
  #: (ptr) -> void
  def zr_deflate_clear_hash(s)
    zr_zlib_set_u32(DeflateState[s].head, DeflateState[s].hash_size - 1, DEF_NIL)
    Libc.memset(DeflateState[s].head, Machine.i32(0), (DeflateState[s].hash_size - 1) * 4)
  end

  # slide_hash: moves each hash chain position down by the window size, or
  # clears it if it goes below zero.
  #: (ptr) -> void
  def zr_deflate_slide_hash(s)
    wsize = DeflateState[s].w_size
    head = DeflateState[s].head
    n = DeflateState[s].hash_size
    while n > 0
      n -= 1
      m = zr_zlib_u32(head, n)
      if m >= wsize
        zr_zlib_set_u32(head, n, m - wsize)
      else
        zr_zlib_set_u32(head, n, DEF_NIL)
      end
    end
    prev = DeflateState[s].prev
    n = wsize
    while n > 0
      n -= 1
      m = zr_zlib_u32(prev, n)
      if m >= wsize
        zr_zlib_set_u32(prev, n, m - wsize)
      else
        zr_zlib_set_u32(prev, n, DEF_NIL)
      end
    end
  end

  # read_buf: reads up to `size` bytes of input into `buf` and adds them
  # to the check value. Returns the number of bytes.
  #: (ptr, ptr, ptr, word) -> word
  def zr_deflate_read_buf(strm, s, buf, size)
    len = ZStream[strm].avail_in
    if len > size
      len = size
    end
    if len == 0
      return 0
    end
    ZStream[strm].avail_in = ZStream[strm].avail_in - len
    Libc.memmove(buf, ZStream[strm].next_in, len)
    if DeflateState[s].wrap == 1
      ZStream[strm].adler = zr_adler32(ZStream[strm].adler, buf, len)
    elsif DeflateState[s].wrap == 2
      ZStream[strm].adler = zr_crc32(ZStream[strm].adler, buf, len)
    end
    ZStream[strm].next_in = ZStream[strm].next_in + len
    ZStream[strm].total_in = ZStream[strm].total_in + len
    len
  end

  # fill_window: fills the window from the input as far as the lookahead
  # needs. It slides the window down when the upper half is full. It sets
  # the bytes after the data to zero, so a match scan reads no undefined
  # bytes.
  #: (ptr) -> void
  def zr_deflate_fill_window(s)
    strm = DeflateState[s].strm
    wsize = DeflateState[s].w_size
    window = DeflateState[s].window
    while true
      more = DeflateState[s].window_size - DeflateState[s].lookahead - DeflateState[s].strstart
      if DeflateState[s].strstart >= wsize + zr_deflate_max_dist(s)
        Libc.memmove(window, window + wsize, wsize - more)
        DeflateState[s].match_start = DeflateState[s].match_start - wsize
        DeflateState[s].strstart = DeflateState[s].strstart - wsize
        DeflateState[s].block_start = DeflateState[s].block_start - wsize
        if DeflateState[s].insert > DeflateState[s].strstart
          DeflateState[s].insert = DeflateState[s].strstart
        end
        zr_deflate_slide_hash(s)
        more += wsize
      end
      if ZStream[strm].avail_in == 0
        break
      end
      n = zr_deflate_read_buf(strm, s, window + DeflateState[s].strstart + DeflateState[s].lookahead, more)
      DeflateState[s].lookahead = DeflateState[s].lookahead + n
      if DeflateState[s].lookahead + DeflateState[s].insert >= MIN_MATCH
        str = DeflateState[s].strstart - DeflateState[s].insert
        ins_h = zr_deflate_window_byte(s, str)
        ins_h = zr_deflate_hash(s, ins_h, zr_deflate_window_byte(s, str + 1))
        DeflateState[s].ins_h = ins_h
        while DeflateState[s].insert != 0
          ins_h = zr_deflate_hash(s, DeflateState[s].ins_h, zr_deflate_window_byte(s, str + MIN_MATCH - 1))
          DeflateState[s].ins_h = ins_h
          zr_zlib_set_u32(DeflateState[s].prev, str & DeflateState[s].w_mask, zr_zlib_u32(DeflateState[s].head, ins_h))
          zr_zlib_set_u32(DeflateState[s].head, ins_h, str)
          str += 1
          DeflateState[s].insert = DeflateState[s].insert - 1
          if DeflateState[s].lookahead + DeflateState[s].insert < MIN_MATCH
            break
          end
        end
      end
      if DeflateState[s].lookahead >= DEF_MIN_LOOKAHEAD || ZStream[strm].avail_in == 0
        break
      end
    end
    if DeflateState[s].high_water < DeflateState[s].window_size
      curr = DeflateState[s].strstart + DeflateState[s].lookahead
      if DeflateState[s].high_water < curr
        init = DeflateState[s].window_size - curr
        if init > DEF_WIN_INIT
          init = DEF_WIN_INIT
        end
        Libc.memset(window + curr, Machine.i32(0), init)
        DeflateState[s].high_water = curr + init
      elsif DeflateState[s].high_water < curr + DEF_WIN_INIT
        init = curr + DEF_WIN_INIT - DeflateState[s].high_water
        if init > DeflateState[s].window_size - DeflateState[s].high_water
          init = DeflateState[s].window_size - DeflateState[s].high_water
        end
        Libc.memset(window + DeflateState[s].high_water, Machine.i32(0), init)
        DeflateState[s].high_water = DeflateState[s].high_water + init
      end
    end
  end

  # deflateStateCheck: returns 1 when `strm` has no valid deflate state.
  #: (ptr) -> word
  def zr_deflate_state_check(strm)
    if strm == 0
      return 1
    end
    s = ZStream[strm].state
    if s == 0 || DeflateState[s].strm != strm
      return 1
    end
    status = DeflateState[s].status
    if status != DEF_INIT_STATE && status != DEF_GZIP_STATE && status != DEF_EXTRA_STATE && status != DEF_NAME_STATE && status != DEF_COMMENT_STATE && status != DEF_HCRC_STATE && status != DEF_BUSY_STATE && status != DEF_FINISH_STATE
      return 1
    end
    0
  end

  # Sets the pointers for the trees, counts, heap and depths into the
  # block after `s`.
  #: (ptr) -> void
  def zr_deflate_point_tail(s)
    p = s + DeflateState.size
    DeflateState[s].dyn_ltree = p
    p += DEF_LTREE_BYTES
    DeflateState[s].dyn_dtree = p
    p += DEF_DTREE_BYTES
    DeflateState[s].bl_tree = p
    p += DEF_BLTREE_BYTES
    DeflateState[s].bl_count = p
    p += DEF_BL_COUNT_BYTES
    DeflateState[s].heap = p
    p += DEF_HEAP_BYTES
    DeflateState[s].depth = p
  end

  # deflateEnd: frees the state and its buffers. Returns Z_DATA_ERROR if
  # the stream is not complete.
  #: (ptr) -> word
  def zr_deflate_end(strm)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    s = ZStream[strm].state
    status = DeflateState[s].status
    if DeflateState[s].pending_buf != 0
      Libc.free(DeflateState[s].pending_buf)
    end
    if DeflateState[s].head != 0
      Libc.free(DeflateState[s].head)
    end
    if DeflateState[s].prev != 0
      Libc.free(DeflateState[s].prev)
    end
    if DeflateState[s].window != 0
      Libc.free(DeflateState[s].window)
    end
    Libc.free(s)
    ZStream[strm].state = 0
    if status == DEF_BUSY_STATE
      return Z_DATA_ERROR
    end
    Z_OK
  end

  # deflateInit2_: gives a stream its state and buffers. The C code has
  # version and size checks against a caller built for a different zlib.
  # Here no caller can be, so the checks are not necessary.
  #: (ptr, word, word, word, word, word) -> word
  def zr_deflate_init2(strm, level, method, window_bits, mem_level, strategy)
    wrap = 1
    if strm == 0
      return Z_STREAM_ERROR
    end
    ZStream[strm].msg = 0
    if level == Z_DEFAULT_COMPRESSION
      level = 6
    end
    if window_bits < 0
      wrap = 0
      if window_bits < 0 - 15
        return Z_STREAM_ERROR
      end
      window_bits = 0 - window_bits
    elsif window_bits > 15
      wrap = 2
      window_bits -= 16
    end
    if mem_level < 1 || mem_level > DEF_MAX_MEM_LEVEL || method != Z_DEFLATED || window_bits < 8 || window_bits > 15 || level < 0 || level > 9 || strategy < 0 || strategy > Z_FIXED || (window_bits == 8 && wrap != 1)
      return Z_STREAM_ERROR
    end
    if window_bits == 8
      window_bits = 9
    end
    s = Libc.malloc(DeflateState.size + DEF_TAIL_BYTES)
    if s == 0
      return Z_MEM_ERROR
    end
    Libc.memset(s, Machine.i32(0), DeflateState.size + DEF_TAIL_BYTES)
    zr_deflate_point_tail(s)
    ZStream[strm].state = s
    DeflateState[s].strm = strm
    DeflateState[s].status = DEF_INIT_STATE
    DeflateState[s].wrap = wrap
    DeflateState[s].w_bits = window_bits
    DeflateState[s].w_size = 1 << window_bits
    DeflateState[s].w_mask = DeflateState[s].w_size - 1
    DeflateState[s].hash_bits = mem_level + 7
    DeflateState[s].hash_size = 1 << DeflateState[s].hash_bits
    DeflateState[s].hash_mask = DeflateState[s].hash_size - 1
    DeflateState[s].hash_shift = (DeflateState[s].hash_bits + MIN_MATCH - 1) / MIN_MATCH
    DeflateState[s].window = Libc.malloc(DeflateState[s].w_size * 2)
    DeflateState[s].prev = Libc.malloc(DeflateState[s].w_size * 4)
    DeflateState[s].head = Libc.malloc(DeflateState[s].hash_size * 4)
    DeflateState[s].high_water = 0
    DeflateState[s].lit_bufsize = 1 << (mem_level + 6)
    DeflateState[s].pending_buf = Libc.malloc(DeflateState[s].lit_bufsize * 4)
    DeflateState[s].pending_buf_size = DeflateState[s].lit_bufsize * 4
    if DeflateState[s].window == 0 || DeflateState[s].prev == 0 || DeflateState[s].head == 0 || DeflateState[s].pending_buf == 0
      DeflateState[s].status = DEF_FINISH_STATE
      ZStream[strm].msg = zr_zlib_error_text(Z_MEM_ERROR)
      zr_deflate_end(strm)
      return Z_MEM_ERROR
    end
    DeflateState[s].sym_buf = DeflateState[s].pending_buf + DeflateState[s].lit_bufsize
    DeflateState[s].sym_end = (DeflateState[s].lit_bufsize - 1) * 3
    DeflateState[s].level = level
    DeflateState[s].strategy = strategy
    zr_deflate_reset(strm)
  end

  # deflateSetDictionary: puts the dictionary into the window and the
  # hash chains, before any input.
  #: (ptr, ptr, word) -> word
  def zr_deflate_set_dictionary(strm, dictionary, dict_length)
    if zr_deflate_state_check(strm) != 0 || dictionary == 0
      return Z_STREAM_ERROR
    end
    s = ZStream[strm].state
    wrap = DeflateState[s].wrap
    if wrap == 2 || (wrap == 1 && DeflateState[s].status != DEF_INIT_STATE) || DeflateState[s].lookahead != 0
      return Z_STREAM_ERROR
    end
    if wrap == 1
      ZStream[strm].adler = zr_adler32(ZStream[strm].adler, dictionary, dict_length)
    end
    DeflateState[s].wrap = 0
    if dict_length >= DeflateState[s].w_size
      if wrap == 0
        zr_deflate_clear_hash(s)
        DeflateState[s].strstart = 0
        DeflateState[s].block_start = 0
        DeflateState[s].insert = 0
      end
      dictionary += dict_length - DeflateState[s].w_size
      dict_length = DeflateState[s].w_size
    end
    avail = ZStream[strm].avail_in
    next_in = ZStream[strm].next_in
    ZStream[strm].avail_in = dict_length
    ZStream[strm].next_in = dictionary
    zr_deflate_fill_window(s)
    while DeflateState[s].lookahead >= MIN_MATCH
      str = DeflateState[s].strstart
      n = DeflateState[s].lookahead - (MIN_MATCH - 1)
      while n > 0
        ins_h = zr_deflate_hash(s, DeflateState[s].ins_h, zr_deflate_window_byte(s, str + MIN_MATCH - 1))
        DeflateState[s].ins_h = ins_h
        zr_zlib_set_u32(DeflateState[s].prev, str & DeflateState[s].w_mask, zr_zlib_u32(DeflateState[s].head, ins_h))
        zr_zlib_set_u32(DeflateState[s].head, ins_h, str)
        str += 1
        n -= 1
      end
      DeflateState[s].strstart = str
      DeflateState[s].lookahead = MIN_MATCH - 1
      zr_deflate_fill_window(s)
    end
    DeflateState[s].strstart = DeflateState[s].strstart + DeflateState[s].lookahead
    DeflateState[s].block_start = DeflateState[s].strstart
    DeflateState[s].insert = DeflateState[s].lookahead
    DeflateState[s].lookahead = 0
    DeflateState[s].match_length = MIN_MATCH - 1
    DeflateState[s].prev_length = MIN_MATCH - 1
    DeflateState[s].match_available = 0
    ZStream[strm].next_in = next_in
    ZStream[strm].avail_in = avail
    DeflateState[s].wrap = wrap
    Z_OK
  end

  # deflateResetKeep: resets the stream to its start, but keeps its
  # window.
  #: (ptr) -> word
  def zr_deflate_reset_keep(strm)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    ZStream[strm].total_in = 0
    ZStream[strm].total_out = 0
    ZStream[strm].msg = 0
    ZStream[strm].data_type = Z_UNKNOWN
    s = ZStream[strm].state
    DeflateState[s].pending = 0
    DeflateState[s].pending_out = DeflateState[s].pending_buf
    if DeflateState[s].wrap < 0
      DeflateState[s].wrap = 0 - DeflateState[s].wrap
    end
    if DeflateState[s].wrap == 2
      DeflateState[s].status = DEF_GZIP_STATE
      ZStream[strm].adler = 0
    else
      DeflateState[s].status = DEF_INIT_STATE
      ZStream[strm].adler = 1
    end
    DeflateState[s].last_flush = 0 - 2
    zr_tr_init(s)
    Z_OK
  end

  # lm_init: sets the matcher's state for a new stream.
  #: (ptr) -> void
  def zr_deflate_lm_init(s)
    DeflateState[s].window_size = 2 * DeflateState[s].w_size
    zr_deflate_clear_hash(s)
    level = DeflateState[s].level
    DeflateState[s].max_lazy_match = zr_deflate_config(level, 1)
    DeflateState[s].good_match = zr_deflate_config(level, 0)
    DeflateState[s].nice_match = zr_deflate_config(level, 2)
    DeflateState[s].max_chain_length = zr_deflate_config(level, 3)
    DeflateState[s].strstart = 0
    DeflateState[s].block_start = 0
    DeflateState[s].lookahead = 0
    DeflateState[s].insert = 0
    DeflateState[s].match_length = MIN_MATCH - 1
    DeflateState[s].prev_length = MIN_MATCH - 1
    DeflateState[s].match_available = 0
    DeflateState[s].ins_h = 0
  end

  # deflateReset
  #: (ptr) -> word
  def zr_deflate_reset(strm)
    ret = zr_deflate_reset_keep(strm)
    if ret == Z_OK
      zr_deflate_lm_init(ZStream[strm].state)
    end
    ret
  end

  # deflateParams: sets a new level and strategy during a stream. It
  # first flushes the data that the old settings compressed.
  #: (ptr, word, word) -> word
  def zr_deflate_params(strm, level, strategy)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    s = ZStream[strm].state
    if level == Z_DEFAULT_COMPRESSION
      level = 6
    end
    if level < 0 || level > 9 || strategy < 0 || strategy > Z_FIXED
      return Z_STREAM_ERROR
    end
    kind = zr_deflate_kind(DeflateState[s].level)
    if (strategy != DeflateState[s].strategy || kind != zr_deflate_kind(level)) && DeflateState[s].last_flush != 0 - 2
      err = zr_deflate(strm, Z_BLOCK)
      if err == Z_STREAM_ERROR
        return err
      end
      if ZStream[strm].avail_in != 0 || (DeflateState[s].strstart - DeflateState[s].block_start) + DeflateState[s].lookahead != 0
        return Z_BUF_ERROR
      end
    end
    if DeflateState[s].level != level
      if DeflateState[s].level == 0 && DeflateState[s].matches != 0
        if DeflateState[s].matches == 1
          zr_deflate_slide_hash(s)
        else
          zr_deflate_clear_hash(s)
        end
        DeflateState[s].matches = 0
      end
      DeflateState[s].level = level
      DeflateState[s].max_lazy_match = zr_deflate_config(level, 1)
      DeflateState[s].good_match = zr_deflate_config(level, 0)
      DeflateState[s].nice_match = zr_deflate_config(level, 2)
      DeflateState[s].max_chain_length = zr_deflate_config(level, 3)
    end
    DeflateState[s].strategy = strategy
    Z_OK
  end

  # putShortMSB: adds a 16-bit word to the pending output, high byte
  # first.
  #: (ptr, word) -> void
  def zr_deflate_put_short_msb(s, b)
    zr_tr_put_byte(s, (b >> 8) & 255)
    zr_tr_put_byte(s, b & 255)
  end

  # flush_pending: writes as much of the pending output as the stream's
  # output buffer can take.
  #: (ptr) -> void
  def zr_deflate_flush_pending(strm)
    s = ZStream[strm].state
    zr_tr_flush_bits(s)
    len = DeflateState[s].pending
    if len > ZStream[strm].avail_out
      len = ZStream[strm].avail_out
    end
    if len == 0
      return
    end
    Libc.memmove(ZStream[strm].next_out, DeflateState[s].pending_out, len)
    ZStream[strm].next_out = ZStream[strm].next_out + len
    DeflateState[s].pending_out = DeflateState[s].pending_out + len
    ZStream[strm].total_out = ZStream[strm].total_out + len
    ZStream[strm].avail_out = ZStream[strm].avail_out - len
    DeflateState[s].pending = DeflateState[s].pending - len
    if DeflateState[s].pending == 0
      DeflateState[s].pending_out = DeflateState[s].pending_buf
    end
  end

  # ERR_RETURN: sets the error's text on the stream and returns the error.
  #: (ptr, word) -> word
  def zr_deflate_err(strm, err)
    ZStream[strm].msg = zr_zlib_error_text(err)
    err
  end

  # deflate: compresses as much of the input as the output buffer allows.
  # It writes the header first, and the trailer after a finish.
  #: (ptr, word) -> word
  def zr_deflate(strm, flush)
    if zr_deflate_state_check(strm) != 0 || flush > Z_BLOCK || flush < 0
      return Z_STREAM_ERROR
    end
    s = ZStream[strm].state
    if ZStream[strm].next_out == 0 || (ZStream[strm].avail_in != 0 && ZStream[strm].next_in == 0) || (DeflateState[s].status == DEF_FINISH_STATE && flush != Z_FINISH)
      return zr_deflate_err(strm, Z_STREAM_ERROR)
    end
    if ZStream[strm].avail_out == 0
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    old_flush = DeflateState[s].last_flush
    DeflateState[s].last_flush = flush
    if DeflateState[s].pending != 0
      zr_deflate_flush_pending(strm)
      if ZStream[strm].avail_out == 0
        DeflateState[s].last_flush = 0 - 1
        return Z_OK
      end
    elsif ZStream[strm].avail_in == 0 && zr_deflate_rank(flush) <= zr_deflate_rank(old_flush) && flush != Z_FINISH
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    if DeflateState[s].status == DEF_FINISH_STATE && ZStream[strm].avail_in != 0
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    if DeflateState[s].status == DEF_INIT_STATE && DeflateState[s].wrap == 0
      DeflateState[s].status = DEF_BUSY_STATE
    end
    if DeflateState[s].status == DEF_INIT_STATE
      header = (Z_DEFLATED + ((DeflateState[s].w_bits - 8) << 4)) << 8
      level_flags = 3
      if DeflateState[s].strategy >= Z_HUFFMAN_ONLY || DeflateState[s].level < 2
        level_flags = 0
      elsif DeflateState[s].level < 6
        level_flags = 1
      elsif DeflateState[s].level == 6
        level_flags = 2
      end
      header = header | (level_flags << 6)
      if DeflateState[s].strstart != 0
        header = header | DEF_PRESET_DICT
      end
      header += 31 - (header % 31)
      zr_deflate_put_short_msb(s, header)
      if DeflateState[s].strstart != 0
        zr_deflate_put_short_msb(s, (ZStream[strm].adler >> 16) & 65535)
        zr_deflate_put_short_msb(s, ZStream[strm].adler & 65535)
      end
      ZStream[strm].adler = 1
      DeflateState[s].status = DEF_BUSY_STATE
      zr_deflate_flush_pending(strm)
      if DeflateState[s].pending != 0
        DeflateState[s].last_flush = 0 - 1
        return Z_OK
      end
    end
    if DeflateState[s].status == DEF_GZIP_STATE
      ZStream[strm].adler = 0
      zr_tr_put_byte(s, 31)
      zr_tr_put_byte(s, 139)
      zr_tr_put_byte(s, 8)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      xfl = 0
      if DeflateState[s].level == 9
        xfl = 2
      elsif DeflateState[s].strategy >= Z_HUFFMAN_ONLY || DeflateState[s].level < 2
        xfl = 4
      end
      zr_tr_put_byte(s, xfl)
      zr_tr_put_byte(s, zr_zlib_os_code())
      DeflateState[s].status = DEF_BUSY_STATE
      zr_deflate_flush_pending(strm)
      if DeflateState[s].pending != 0
        DeflateState[s].last_flush = 0 - 1
        return Z_OK
      end
    end
    if ZStream[strm].avail_in != 0 || DeflateState[s].lookahead != 0 || (flush != Z_NO_FLUSH && DeflateState[s].status != DEF_FINISH_STATE)
      bstate = DEF_NEED_MORE
      if DeflateState[s].level == 0
        bstate = zr_deflate_stored(s, flush)
      elsif DeflateState[s].strategy == Z_HUFFMAN_ONLY
        bstate = zr_deflate_huff(s, flush)
      elsif DeflateState[s].strategy == Z_RLE
        bstate = zr_deflate_rle(s, flush)
      elsif zr_deflate_kind(DeflateState[s].level) == DEF_KIND_FAST
        bstate = zr_deflate_fast(s, flush)
      else
        bstate = zr_deflate_slow(s, flush)
      end
      if bstate == DEF_FINISH_STARTED || bstate == DEF_FINISH_DONE
        DeflateState[s].status = DEF_FINISH_STATE
      end
      if bstate == DEF_NEED_MORE || bstate == DEF_FINISH_STARTED
        if ZStream[strm].avail_out == 0
          DeflateState[s].last_flush = 0 - 1
        end
        return Z_OK
      end
      if bstate == DEF_BLOCK_DONE
        if flush == Z_PARTIAL_FLUSH
          zr_tr_align(s)
        elsif flush != Z_BLOCK
          zr_tr_stored_block(s, 0, 0, 0)
          if flush == Z_FULL_FLUSH
            zr_deflate_clear_hash(s)
            if DeflateState[s].lookahead == 0
              DeflateState[s].strstart = 0
              DeflateState[s].block_start = 0
              DeflateState[s].insert = 0
            end
          end
        end
        zr_deflate_flush_pending(strm)
        if ZStream[strm].avail_out == 0
          DeflateState[s].last_flush = 0 - 1
          return Z_OK
        end
      end
    end
    if flush != Z_FINISH
      return Z_OK
    end
    if DeflateState[s].wrap <= 0
      return Z_STREAM_END
    end
    if DeflateState[s].wrap == 2
      adler = ZStream[strm].adler
      zr_tr_put_byte(s, adler & 255)
      zr_tr_put_byte(s, (adler >> 8) & 255)
      zr_tr_put_byte(s, (adler >> 16) & 255)
      zr_tr_put_byte(s, (adler >> 24) & 255)
      total_in = ZStream[strm].total_in
      zr_tr_put_byte(s, total_in & 255)
      zr_tr_put_byte(s, (total_in >> 8) & 255)
      zr_tr_put_byte(s, (total_in >> 16) & 255)
      zr_tr_put_byte(s, (total_in >> 24) & 255)
    else
      zr_deflate_put_short_msb(s, (ZStream[strm].adler >> 16) & 65535)
      zr_deflate_put_short_msb(s, ZStream[strm].adler & 65535)
    end
    zr_deflate_flush_pending(strm)
    if DeflateState[s].wrap > 0
      DeflateState[s].wrap = 0 - DeflateState[s].wrap
    end
    if DeflateState[s].pending != 0
      return Z_OK
    end
    Z_STREAM_END
  end

  # deflateCopy: makes `dest` a copy of `source`, with all its buffers.
  #: (ptr, ptr) -> word
  def zr_deflate_copy(dest, source)
    if zr_deflate_state_check(source) != 0 || dest == 0
      return Z_STREAM_ERROR
    end
    ss = ZStream[source].state
    Libc.memmove(dest, source, ZStream.size)
    ds = Libc.malloc(DeflateState.size + DEF_TAIL_BYTES)
    if ds == 0
      return Z_MEM_ERROR
    end
    ZStream[dest].state = ds
    Libc.memmove(ds, ss, DeflateState.size + DEF_TAIL_BYTES)
    zr_deflate_point_tail(ds)
    DeflateState[ds].strm = dest
    DeflateState[ds].window = Libc.malloc(DeflateState[ds].w_size * 2)
    DeflateState[ds].prev = Libc.malloc(DeflateState[ds].w_size * 4)
    DeflateState[ds].head = Libc.malloc(DeflateState[ds].hash_size * 4)
    DeflateState[ds].pending_buf = Libc.malloc(DeflateState[ds].lit_bufsize * 4)
    if DeflateState[ds].window == 0 || DeflateState[ds].prev == 0 || DeflateState[ds].head == 0 || DeflateState[ds].pending_buf == 0
      zr_deflate_end(dest)
      return Z_MEM_ERROR
    end
    Libc.memmove(DeflateState[ds].window, DeflateState[ss].window, DeflateState[ds].w_size * 2)
    Libc.memmove(DeflateState[ds].prev, DeflateState[ss].prev, DeflateState[ds].w_size * 4)
    Libc.memmove(DeflateState[ds].head, DeflateState[ss].head, DeflateState[ds].hash_size * 4)
    Libc.memmove(DeflateState[ds].pending_buf, DeflateState[ss].pending_buf, DeflateState[ds].lit_bufsize * 4)
    DeflateState[ds].pending_out = DeflateState[ds].pending_buf + (DeflateState[ss].pending_out - DeflateState[ss].pending_buf)
    DeflateState[ds].sym_buf = DeflateState[ds].pending_buf + DeflateState[ds].lit_bufsize
    Z_OK
  end

  # longest_match: finds the longest match for the string at strstart
  # along the hash chain from `cur_match`, at least prev_length long. It
  # writes the match start to match_start. As in the C code, the scan can
  # read past the lookahead into bytes that fill_window set to zero. The
  # lookahead limits the length, so the result does not depend on them.
  #: (ptr, word) -> word
  def zr_deflate_longest_match(s, cur_match)
    chain_length = DeflateState[s].max_chain_length
    window = DeflateState[s].window
    strstart = DeflateState[s].strstart
    scan = window + strstart
    best_len = DeflateState[s].prev_length
    nice_match = DeflateState[s].nice_match
    limit = DEF_NIL
    if strstart > zr_deflate_max_dist(s)
      limit = strstart - zr_deflate_max_dist(s)
    end
    prev = DeflateState[s].prev
    wmask = DeflateState[s].w_mask
    strend = window + strstart + MAX_MATCH
    scan_end1 = zr_zlib_byte(scan + best_len - 1)
    scan_end = zr_zlib_byte(scan + best_len)
    if DeflateState[s].prev_length >= DeflateState[s].good_match
      chain_length = chain_length >> 2
    end
    if nice_match > DeflateState[s].lookahead
      nice_match = DeflateState[s].lookahead
    end
    while true
      match = window + cur_match
      skip = false
      if zr_zlib_byte(match + best_len) != scan_end || zr_zlib_byte(match + best_len - 1) != scan_end1 || zr_zlib_byte(match) != zr_zlib_byte(scan)
        skip = true
      else
        match += 1
        if zr_zlib_byte(match) != zr_zlib_byte(scan + 1)
          skip = true
        end
      end
      if !skip
        scan += 2
        match += 1
        while true
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          scan += 1
          match += 1
          if zr_zlib_byte(scan) != zr_zlib_byte(match)
            break
          end
          if scan >= strend
            break
          end
        end
        len = MAX_MATCH - (strend - scan)
        scan = strend - MAX_MATCH
        if len > best_len
          DeflateState[s].match_start = cur_match
          best_len = len
          if len >= nice_match
            break
          end
          scan_end1 = zr_zlib_byte(scan + best_len - 1)
          scan_end = zr_zlib_byte(scan + best_len)
        end
      end
      cur_match = zr_zlib_u32(prev, cur_match & wmask)
      if cur_match <= limit
        break
      end
      chain_length -= 1
      if chain_length == 0
        break
      end
    end
    if best_len <= DeflateState[s].lookahead
      return best_len
    end
    DeflateState[s].lookahead
  end

  # FLUSH_BLOCK_ONLY: writes the current block and starts a new one.
  #: (ptr, word) -> void
  def zr_deflate_flush_block_only(s, last)
    buf = 0
    if DeflateState[s].block_start >= 0
      buf = DeflateState[s].window + DeflateState[s].block_start
    end
    zr_tr_flush_block(s, buf, DeflateState[s].strstart - DeflateState[s].block_start, last)
    DeflateState[s].block_start = DeflateState[s].strstart
    zr_deflate_flush_pending(DeflateState[s].strm)
  end

  # deflate_stored: copies the input to stored blocks. It copies directly
  # to the output when the data fits, and through the window and the
  # pending buffer when it does not.
  #: (ptr, word) -> word
  def zr_deflate_stored(s, flush)
    strm = DeflateState[s].strm
    min_block = DeflateState[s].pending_buf_size - 5
    if min_block > DeflateState[s].w_size
      min_block = DeflateState[s].w_size
    end
    last = 0
    used = ZStream[strm].avail_in
    while true
      len = DEF_MAX_STORED
      have = (DeflateState[s].bi_valid + 42) >> 3
      if ZStream[strm].avail_out < have
        break
      end
      have = ZStream[strm].avail_out - have
      left = DeflateState[s].strstart - DeflateState[s].block_start
      if len > left + ZStream[strm].avail_in
        len = left + ZStream[strm].avail_in
      end
      if len > have
        len = have
      end
      if len < min_block && ((len == 0 && flush != Z_FINISH) || flush == Z_NO_FLUSH || len != left + ZStream[strm].avail_in)
        break
      end
      last = 0
      if flush == Z_FINISH && len == left + ZStream[strm].avail_in
        last = 1
      end
      zr_tr_stored_block(s, 0, 0, last)
      pending_buf = DeflateState[s].pending_buf
      pending = DeflateState[s].pending
      Machine.store8(pending_buf + pending - 4, 0, Machine.i8(len))
      Machine.store8(pending_buf + pending - 3, 0, Machine.i8(len >> 8))
      Machine.store8(pending_buf + pending - 2, 0, Machine.i8(len ^ ZLIB_MASK32))
      Machine.store8(pending_buf + pending - 1, 0, Machine.i8((len ^ ZLIB_MASK32) >> 8))
      zr_deflate_flush_pending(strm)
      if left != 0
        if left > len
          left = len
        end
        Libc.memmove(ZStream[strm].next_out, DeflateState[s].window + DeflateState[s].block_start, left)
        ZStream[strm].next_out = ZStream[strm].next_out + left
        ZStream[strm].avail_out = ZStream[strm].avail_out - left
        ZStream[strm].total_out = ZStream[strm].total_out + left
        DeflateState[s].block_start = DeflateState[s].block_start + left
        len -= left
      end
      if len != 0
        zr_deflate_read_buf(strm, s, ZStream[strm].next_out, len)
        ZStream[strm].next_out = ZStream[strm].next_out + len
        ZStream[strm].avail_out = ZStream[strm].avail_out - len
        ZStream[strm].total_out = ZStream[strm].total_out + len
      end
      if last != 0
        break
      end
    end
    used -= ZStream[strm].avail_in
    if used != 0
      w_size = DeflateState[s].w_size
      if used >= w_size
        DeflateState[s].matches = 2
        Libc.memmove(DeflateState[s].window, ZStream[strm].next_in - w_size, w_size)
        DeflateState[s].strstart = w_size
        DeflateState[s].insert = w_size
      else
        if DeflateState[s].window_size - DeflateState[s].strstart <= used
          DeflateState[s].strstart = DeflateState[s].strstart - w_size
          Libc.memmove(DeflateState[s].window, DeflateState[s].window + w_size, DeflateState[s].strstart)
          if DeflateState[s].matches < 2
            DeflateState[s].matches = DeflateState[s].matches + 1
          end
          if DeflateState[s].insert > DeflateState[s].strstart
            DeflateState[s].insert = DeflateState[s].strstart
          end
        end
        Libc.memmove(DeflateState[s].window + DeflateState[s].strstart, ZStream[strm].next_in - used, used)
        DeflateState[s].strstart = DeflateState[s].strstart + used
        room = w_size - DeflateState[s].insert
        if used < room
          room = used
        end
        DeflateState[s].insert = DeflateState[s].insert + room
      end
      DeflateState[s].block_start = DeflateState[s].strstart
    end
    if DeflateState[s].high_water < DeflateState[s].strstart
      DeflateState[s].high_water = DeflateState[s].strstart
    end
    if last != 0
      return DEF_FINISH_DONE
    end
    if flush != Z_NO_FLUSH && flush != Z_FINISH && ZStream[strm].avail_in == 0 && DeflateState[s].strstart == DeflateState[s].block_start
      return DEF_BLOCK_DONE
    end
    have = DeflateState[s].window_size - DeflateState[s].strstart
    if ZStream[strm].avail_in > have && DeflateState[s].block_start >= DeflateState[s].w_size
      w_size = DeflateState[s].w_size
      DeflateState[s].block_start = DeflateState[s].block_start - w_size
      DeflateState[s].strstart = DeflateState[s].strstart - w_size
      Libc.memmove(DeflateState[s].window, DeflateState[s].window + w_size, DeflateState[s].strstart)
      if DeflateState[s].matches < 2
        DeflateState[s].matches = DeflateState[s].matches + 1
      end
      have += w_size
      if DeflateState[s].insert > DeflateState[s].strstart
        DeflateState[s].insert = DeflateState[s].strstart
      end
    end
    if have > ZStream[strm].avail_in
      have = ZStream[strm].avail_in
    end
    if have != 0
      zr_deflate_read_buf(strm, s, DeflateState[s].window + DeflateState[s].strstart, have)
      DeflateState[s].strstart = DeflateState[s].strstart + have
      room = DeflateState[s].w_size - DeflateState[s].insert
      if have < room
        room = have
      end
      DeflateState[s].insert = DeflateState[s].insert + room
    end
    if DeflateState[s].high_water < DeflateState[s].strstart
      DeflateState[s].high_water = DeflateState[s].strstart
    end
    have = (DeflateState[s].bi_valid + 42) >> 3
    have = DeflateState[s].pending_buf_size - have
    if have > DEF_MAX_STORED
      have = DEF_MAX_STORED
    end
    min_block = have
    if min_block > DeflateState[s].w_size
      min_block = DeflateState[s].w_size
    end
    left = DeflateState[s].strstart - DeflateState[s].block_start
    if left >= min_block || ((left != 0 || flush == Z_FINISH) && flush != Z_NO_FLUSH && ZStream[strm].avail_in == 0 && left <= have)
      len = left
      if len > have
        len = have
      end
      last = 0
      if flush == Z_FINISH && ZStream[strm].avail_in == 0 && len == left
        last = 1
      end
      zr_tr_stored_block(s, DeflateState[s].window + DeflateState[s].block_start, len, last)
      DeflateState[s].block_start = DeflateState[s].block_start + len
      zr_deflate_flush_pending(strm)
    end
    if last != 0
      return DEF_FINISH_STARTED
    end
    DEF_NEED_MORE
  end

  # The end of a block function. Returns the value that the C FLUSH_BLOCK
  # returns when the output is full, or -1 to continue.
  #: (ptr, word) -> word
  def zr_deflate_flush_block(s, last)
    zr_deflate_flush_block_only(s, last)
    if ZStream[DeflateState[s].strm].avail_out == 0
      if last != 0
        return DEF_FINISH_STARTED
      end
      return DEF_NEED_MORE
    end
    0 - 1
  end

  # The step that each block function does when no input remains. On a
  # finish, it flushes the last block. If not, it flushes the current
  # block.
  #: (ptr, word) -> word
  def zr_deflate_block_end(s, flush)
    if flush == Z_FINISH
      r = zr_deflate_flush_block(s, 1)
      if r >= 0
        return r
      end
      return DEF_FINISH_DONE
    end
    if DeflateState[s].sym_next != 0
      r = zr_deflate_flush_block(s, 0)
      if r >= 0
        return r
      end
    end
    DEF_BLOCK_DONE
  end

  # deflate_fast: uses each match when it finds it, with no lazy
  # evaluation.
  #: (ptr, word) -> word
  def zr_deflate_fast(s, flush)
    while true
      if DeflateState[s].lookahead < DEF_MIN_LOOKAHEAD
        zr_deflate_fill_window(s)
        if DeflateState[s].lookahead < DEF_MIN_LOOKAHEAD && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState[s].lookahead == 0
          break
        end
      end
      hash_head = DEF_NIL
      if DeflateState[s].lookahead >= MIN_MATCH
        hash_head = zr_deflate_insert_string(s, DeflateState[s].strstart)
      end
      if hash_head != DEF_NIL && Machine.ptr(DeflateState[s].strstart - hash_head) <= zr_deflate_max_dist(s)
        DeflateState[s].match_length = zr_deflate_longest_match(s, hash_head)
      end
      bflush = 0
      if DeflateState[s].match_length >= MIN_MATCH
        bflush = zr_tr_tally(s, DeflateState[s].strstart - DeflateState[s].match_start, DeflateState[s].match_length - MIN_MATCH)
        DeflateState[s].lookahead = DeflateState[s].lookahead - DeflateState[s].match_length
        if DeflateState[s].match_length <= DeflateState[s].max_lazy_match && DeflateState[s].lookahead >= MIN_MATCH
          DeflateState[s].match_length = DeflateState[s].match_length - 1
          while true
            DeflateState[s].strstart = DeflateState[s].strstart + 1
            zr_deflate_insert_string(s, DeflateState[s].strstart)
            DeflateState[s].match_length = DeflateState[s].match_length - 1
            if DeflateState[s].match_length == 0
              break
            end
          end
          DeflateState[s].strstart = DeflateState[s].strstart + 1
        else
          DeflateState[s].strstart = DeflateState[s].strstart + DeflateState[s].match_length
          DeflateState[s].match_length = 0
          ins_h = zr_deflate_window_byte(s, DeflateState[s].strstart)
          DeflateState[s].ins_h = zr_deflate_hash(s, ins_h, zr_deflate_window_byte(s, DeflateState[s].strstart + 1))
        end
      else
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState[s].strstart))
        DeflateState[s].lookahead = DeflateState[s].lookahead - 1
        DeflateState[s].strstart = DeflateState[s].strstart + 1
      end
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    if DeflateState[s].strstart < MIN_MATCH - 1
      DeflateState[s].insert = DeflateState[s].strstart
    else
      DeflateState[s].insert = MIN_MATCH - 1
    end
    zr_deflate_block_end(s, flush)
  end

  # deflate_slow: lazy evaluation. It keeps a match back in case the next
  # byte starts a longer match.
  #: (ptr, word) -> word
  def zr_deflate_slow(s, flush)
    while true
      if DeflateState[s].lookahead < DEF_MIN_LOOKAHEAD
        zr_deflate_fill_window(s)
        if DeflateState[s].lookahead < DEF_MIN_LOOKAHEAD && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState[s].lookahead == 0
          break
        end
      end
      hash_head = DEF_NIL
      if DeflateState[s].lookahead >= MIN_MATCH
        hash_head = zr_deflate_insert_string(s, DeflateState[s].strstart)
      end
      DeflateState[s].prev_length = DeflateState[s].match_length
      DeflateState[s].prev_match = DeflateState[s].match_start
      DeflateState[s].match_length = MIN_MATCH - 1
      if hash_head != DEF_NIL && DeflateState[s].prev_length < DeflateState[s].max_lazy_match && Machine.ptr(DeflateState[s].strstart - hash_head) <= zr_deflate_max_dist(s)
        DeflateState[s].match_length = zr_deflate_longest_match(s, hash_head)
        if DeflateState[s].match_length <= 5 && (DeflateState[s].strategy == Z_FILTERED || (DeflateState[s].match_length == MIN_MATCH && DeflateState[s].strstart - DeflateState[s].match_start > DEF_TOO_FAR))
          DeflateState[s].match_length = MIN_MATCH - 1
        end
      end
      if DeflateState[s].prev_length >= MIN_MATCH && DeflateState[s].match_length <= DeflateState[s].prev_length
        max_insert = DeflateState[s].strstart + DeflateState[s].lookahead - MIN_MATCH
        bflush = zr_tr_tally(s, DeflateState[s].strstart - 1 - DeflateState[s].prev_match, DeflateState[s].prev_length - MIN_MATCH)
        DeflateState[s].lookahead = DeflateState[s].lookahead - (DeflateState[s].prev_length - 1)
        DeflateState[s].prev_length = DeflateState[s].prev_length - 2
        while true
          DeflateState[s].strstart = DeflateState[s].strstart + 1
          if DeflateState[s].strstart <= max_insert
            zr_deflate_insert_string(s, DeflateState[s].strstart)
          end
          DeflateState[s].prev_length = DeflateState[s].prev_length - 1
          if DeflateState[s].prev_length == 0
            break
          end
        end
        DeflateState[s].match_available = 0
        DeflateState[s].match_length = MIN_MATCH - 1
        DeflateState[s].strstart = DeflateState[s].strstart + 1
        if bflush != 0
          r = zr_deflate_flush_block(s, 0)
          if r >= 0
            return r
          end
        end
      elsif DeflateState[s].match_available != 0
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState[s].strstart - 1))
        if bflush != 0
          zr_deflate_flush_block_only(s, 0)
        end
        DeflateState[s].strstart = DeflateState[s].strstart + 1
        DeflateState[s].lookahead = DeflateState[s].lookahead - 1
        if ZStream[DeflateState[s].strm].avail_out == 0
          return DEF_NEED_MORE
        end
      else
        DeflateState[s].match_available = 1
        DeflateState[s].strstart = DeflateState[s].strstart + 1
        DeflateState[s].lookahead = DeflateState[s].lookahead - 1
      end
    end
    if DeflateState[s].match_available != 0
      zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState[s].strstart - 1))
      DeflateState[s].match_available = 0
    end
    if DeflateState[s].strstart < MIN_MATCH - 1
      DeflateState[s].insert = DeflateState[s].strstart
    else
      DeflateState[s].insert = MIN_MATCH - 1
    end
    zr_deflate_block_end(s, flush)
  end

  # deflate_rle: encodes runs of one byte as matches at distance one.
  #: (ptr, word) -> word
  def zr_deflate_rle(s, flush)
    while true
      if DeflateState[s].lookahead <= MAX_MATCH
        zr_deflate_fill_window(s)
        if DeflateState[s].lookahead <= MAX_MATCH && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState[s].lookahead == 0
          break
        end
      end
      DeflateState[s].match_length = 0
      if DeflateState[s].lookahead >= MIN_MATCH && DeflateState[s].strstart > 0
        window = DeflateState[s].window
        scan = window + DeflateState[s].strstart - 1
        prev = zr_zlib_byte(scan)
        if prev == zr_zlib_byte(scan + 1) && prev == zr_zlib_byte(scan + 2) && prev == zr_zlib_byte(scan + 3)
          scan += 3
          strend = window + DeflateState[s].strstart + MAX_MATCH
          while true
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            scan += 1
            if prev != zr_zlib_byte(scan)
              break
            end
            if scan >= strend
              break
            end
          end
          DeflateState[s].match_length = MAX_MATCH - (strend - scan)
          if DeflateState[s].match_length > DeflateState[s].lookahead
            DeflateState[s].match_length = DeflateState[s].lookahead
          end
        end
      end
      bflush = 0
      if DeflateState[s].match_length >= MIN_MATCH
        bflush = zr_tr_tally(s, 1, DeflateState[s].match_length - MIN_MATCH)
        DeflateState[s].lookahead = DeflateState[s].lookahead - DeflateState[s].match_length
        DeflateState[s].strstart = DeflateState[s].strstart + DeflateState[s].match_length
        DeflateState[s].match_length = 0
      else
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState[s].strstart))
        DeflateState[s].lookahead = DeflateState[s].lookahead - 1
        DeflateState[s].strstart = DeflateState[s].strstart + 1
      end
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    DeflateState[s].insert = 0
    zr_deflate_block_end(s, flush)
  end

  # deflate_huff: encodes each byte as a literal, with no matching.
  #: (ptr, word) -> word
  def zr_deflate_huff(s, flush)
    while true
      if DeflateState[s].lookahead == 0
        zr_deflate_fill_window(s)
        if DeflateState[s].lookahead == 0
          if flush == Z_NO_FLUSH
            return DEF_NEED_MORE
          end
          break
        end
      end
      DeflateState[s].match_length = 0
      bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState[s].strstart))
      DeflateState[s].lookahead = DeflateState[s].lookahead - 1
      DeflateState[s].strstart = DeflateState[s].strstart + 1
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    DeflateState[s].insert = 0
    zr_deflate_block_end(s, flush)
  end
end
