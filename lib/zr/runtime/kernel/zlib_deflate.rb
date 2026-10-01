module Zr::Kern
  # deflate.c: the compressor. The state is the C deflate_state, with its
  # trees, counts, heap and depths in one block after it. The four buffers
  # that the C code allocates separately are also separate here. Nothing
  # calls deflateSetHeader, so no gzip header struct is set, and a gzip
  # stream gets the plain ten-byte header.
  # Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.
  DeflateState = layout strm: Ptr, status: Word, pending_buf: Ptr, pending_buf_size: Word, pending_out: Ptr, pending: Word, wrap: Word, last_flush: Word, w_size: Word, w_bits: Word, w_mask: Word, window: Ptr, window_size: Word, prev: Ptr, head: Ptr, ins_h: Word, hash_size: Word, hash_bits: Word, hash_mask: Word, hash_shift: Word, block_start: Word, match_length: Word, prev_match: Word, match_available: Word, strstart: Word, match_start: Word, lookahead: Word, prev_length: Word, max_chain_length: Word, max_lazy_match: Word, level: Word, strategy: Word, good_match: Word, nice_match: Word, dyn_ltree: Ptr, dyn_dtree: Ptr, bl_tree: Ptr, l_max_code: Word, d_max_code: Word, bl_max_code: Word, bl_count: Ptr, heap: Ptr, heap_len: Word, heap_max: Word, depth: Ptr, sym_buf: Ptr, lit_bufsize: Word, sym_next: Word, sym_end: Word, opt_len: Word, static_len: Word, matches: Word, insert: Word, bi_buf: Word, bi_valid: Word, high_water: Word

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
  sig [Word, Word] => Word
  def zr_deflate_config(level, col)
    zr_zlib_u32(zr_deflate_config_table(), (level * 4) + col)
  end

  # The func column of the configuration table: the block function that a
  # level runs.
  sig [Word] => Word
  def zr_deflate_kind(level)
    if level == 0
      return DEF_KIND_STORED
    elsif level <= 3
      return DEF_KIND_FAST
    end
    DEF_KIND_SLOW
  end

  # MAX_DIST
  sig [Ptr] => Word
  def zr_deflate_max_dist(s)
    DeflateState.w_size(s) - DEF_MIN_LOOKAHEAD
  end

  # RANK: puts Z_BLOCK between Z_NO_FLUSH and Z_PARTIAL_FLUSH.
  sig [Word] => Word
  def zr_deflate_rank(f)
    if f > 4
      return (f * 2) - 9
    end
    f * 2
  end

  # UPDATE_HASH: returns the hash `h` updated with the byte `c`.
  sig [Ptr, Word, Word] => Word
  def zr_deflate_hash(s, h, c)
    ((h << DeflateState.hash_shift(s)) ^ c) & DeflateState.hash_mask(s)
  end

  sig [Ptr, Word] => Word
  def zr_deflate_window_byte(s, i)
    zr_zlib_byte(DeflateState.window(s) + i)
  end

  # INSERT_STRING: inserts the string at `str` into the hash chains.
  # Returns the previous head of its hash chain.
  sig [Ptr, Word] => Word
  def zr_deflate_insert_string(s, str)
    ins_h = zr_deflate_hash(s, DeflateState.ins_h(s), zr_deflate_window_byte(s, str + MIN_MATCH - 1))
    DeflateState.set_ins_h(s, ins_h)
    match_head = zr_zlib_u32(DeflateState.head(s), ins_h)
    zr_zlib_set_u32(DeflateState.prev(s), str & DeflateState.w_mask(s), match_head)
    zr_zlib_set_u32(DeflateState.head(s), ins_h, str)
    match_head
  end

  # CLEAR_HASH
  sig [Ptr] => Void
  def zr_deflate_clear_hash(s)
    zr_zlib_set_u32(DeflateState.head(s), DeflateState.hash_size(s) - 1, DEF_NIL)
    Libc.memset(DeflateState.head(s), Machine.i32(0), (DeflateState.hash_size(s) - 1) * 4)
  end

  # slide_hash: moves each hash chain position down by the window size, or
  # clears it if it goes below zero.
  sig [Ptr] => Void
  def zr_deflate_slide_hash(s)
    wsize = DeflateState.w_size(s)
    head = DeflateState.head(s)
    n = DeflateState.hash_size(s)
    while n > 0
      n -= 1
      m = zr_zlib_u32(head, n)
      if m >= wsize
        zr_zlib_set_u32(head, n, m - wsize)
      else
        zr_zlib_set_u32(head, n, DEF_NIL)
      end
    end
    prev = DeflateState.prev(s)
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
  sig [Ptr, Ptr, Ptr, Word] => Word
  def zr_deflate_read_buf(strm, s, buf, size)
    len = ZStream.avail_in(strm)
    if len > size
      len = size
    end
    if len == 0
      return 0
    end
    ZStream.set_avail_in(strm, ZStream.avail_in(strm) - len)
    Libc.memmove(buf, ZStream.next_in(strm), len)
    if DeflateState.wrap(s) == 1
      ZStream.set_adler(strm, zr_adler32(ZStream.adler(strm), buf, len))
    elsif DeflateState.wrap(s) == 2
      ZStream.set_adler(strm, zr_crc32(ZStream.adler(strm), buf, len))
    end
    ZStream.set_next_in(strm, ZStream.next_in(strm) + len)
    ZStream.set_total_in(strm, ZStream.total_in(strm) + len)
    len
  end

  # fill_window: fills the window from the input as far as the lookahead
  # needs. It slides the window down when the upper half is full. It sets
  # the bytes after the data to zero, so a match scan reads no undefined
  # bytes.
  sig [Ptr] => Void
  def zr_deflate_fill_window(s)
    strm = DeflateState.strm(s)
    wsize = DeflateState.w_size(s)
    window = DeflateState.window(s)
    while true
      more = DeflateState.window_size(s) - DeflateState.lookahead(s) - DeflateState.strstart(s)
      if DeflateState.strstart(s) >= wsize + zr_deflate_max_dist(s)
        Libc.memmove(window, window + wsize, wsize - more)
        DeflateState.set_match_start(s, DeflateState.match_start(s) - wsize)
        DeflateState.set_strstart(s, DeflateState.strstart(s) - wsize)
        DeflateState.set_block_start(s, DeflateState.block_start(s) - wsize)
        if DeflateState.insert(s) > DeflateState.strstart(s)
          DeflateState.set_insert(s, DeflateState.strstart(s))
        end
        zr_deflate_slide_hash(s)
        more += wsize
      end
      if ZStream.avail_in(strm) == 0
        break
      end
      n = zr_deflate_read_buf(strm, s, window + DeflateState.strstart(s) + DeflateState.lookahead(s), more)
      DeflateState.set_lookahead(s, DeflateState.lookahead(s) + n)
      if DeflateState.lookahead(s) + DeflateState.insert(s) >= MIN_MATCH
        str = DeflateState.strstart(s) - DeflateState.insert(s)
        ins_h = zr_deflate_window_byte(s, str)
        ins_h = zr_deflate_hash(s, ins_h, zr_deflate_window_byte(s, str + 1))
        DeflateState.set_ins_h(s, ins_h)
        while DeflateState.insert(s) != 0
          ins_h = zr_deflate_hash(s, DeflateState.ins_h(s), zr_deflate_window_byte(s, str + MIN_MATCH - 1))
          DeflateState.set_ins_h(s, ins_h)
          zr_zlib_set_u32(DeflateState.prev(s), str & DeflateState.w_mask(s), zr_zlib_u32(DeflateState.head(s), ins_h))
          zr_zlib_set_u32(DeflateState.head(s), ins_h, str)
          str += 1
          DeflateState.set_insert(s, DeflateState.insert(s) - 1)
          if DeflateState.lookahead(s) + DeflateState.insert(s) < MIN_MATCH
            break
          end
        end
      end
      if DeflateState.lookahead(s) >= DEF_MIN_LOOKAHEAD || ZStream.avail_in(strm) == 0
        break
      end
    end
    if DeflateState.high_water(s) < DeflateState.window_size(s)
      curr = DeflateState.strstart(s) + DeflateState.lookahead(s)
      if DeflateState.high_water(s) < curr
        init = DeflateState.window_size(s) - curr
        if init > DEF_WIN_INIT
          init = DEF_WIN_INIT
        end
        Libc.memset(window + curr, Machine.i32(0), init)
        DeflateState.set_high_water(s, curr + init)
      elsif DeflateState.high_water(s) < curr + DEF_WIN_INIT
        init = curr + DEF_WIN_INIT - DeflateState.high_water(s)
        if init > DeflateState.window_size(s) - DeflateState.high_water(s)
          init = DeflateState.window_size(s) - DeflateState.high_water(s)
        end
        Libc.memset(window + DeflateState.high_water(s), Machine.i32(0), init)
        DeflateState.set_high_water(s, DeflateState.high_water(s) + init)
      end
    end
  end

  # deflateStateCheck: returns 1 when `strm` has no valid deflate state.
  sig [Ptr] => Word
  def zr_deflate_state_check(strm)
    if strm == 0
      return 1
    end
    s = ZStream.state(strm)
    if s == 0 || DeflateState.strm(s) != strm
      return 1
    end
    status = DeflateState.status(s)
    if status != DEF_INIT_STATE && status != DEF_GZIP_STATE && status != DEF_EXTRA_STATE && status != DEF_NAME_STATE && status != DEF_COMMENT_STATE && status != DEF_HCRC_STATE && status != DEF_BUSY_STATE && status != DEF_FINISH_STATE
      return 1
    end
    0
  end

  # Sets the pointers for the trees, counts, heap and depths into the
  # block after `s`.
  sig [Ptr] => Void
  def zr_deflate_point_tail(s)
    p = s + DeflateState.size
    DeflateState.set_dyn_ltree(s, p)
    p += DEF_LTREE_BYTES
    DeflateState.set_dyn_dtree(s, p)
    p += DEF_DTREE_BYTES
    DeflateState.set_bl_tree(s, p)
    p += DEF_BLTREE_BYTES
    DeflateState.set_bl_count(s, p)
    p += DEF_BL_COUNT_BYTES
    DeflateState.set_heap(s, p)
    p += DEF_HEAP_BYTES
    DeflateState.set_depth(s, p)
  end

  # deflateEnd: frees the state and its buffers. Returns Z_DATA_ERROR if
  # the stream is not complete.
  sig [Ptr] => Word
  def zr_deflate_end(strm)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    s = ZStream.state(strm)
    status = DeflateState.status(s)
    if DeflateState.pending_buf(s) != 0
      Libc.free(DeflateState.pending_buf(s))
    end
    if DeflateState.head(s) != 0
      Libc.free(DeflateState.head(s))
    end
    if DeflateState.prev(s) != 0
      Libc.free(DeflateState.prev(s))
    end
    if DeflateState.window(s) != 0
      Libc.free(DeflateState.window(s))
    end
    Libc.free(s)
    ZStream.set_state(strm, 0)
    if status == DEF_BUSY_STATE
      return Z_DATA_ERROR
    end
    Z_OK
  end

  # deflateInit2_: gives a stream its state and buffers. The C code has
  # version and size checks against a caller built for a different zlib.
  # Here no caller can be, so the checks are not necessary.
  sig [Ptr, Word, Word, Word, Word, Word] => Word
  def zr_deflate_init2(strm, level, method, window_bits, mem_level, strategy)
    wrap = 1
    if strm == 0
      return Z_STREAM_ERROR
    end
    ZStream.set_msg(strm, 0)
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
    ZStream.set_state(strm, s)
    DeflateState.set_strm(s, strm)
    DeflateState.set_status(s, DEF_INIT_STATE)
    DeflateState.set_wrap(s, wrap)
    DeflateState.set_w_bits(s, window_bits)
    DeflateState.set_w_size(s, 1 << window_bits)
    DeflateState.set_w_mask(s, DeflateState.w_size(s) - 1)
    DeflateState.set_hash_bits(s, mem_level + 7)
    DeflateState.set_hash_size(s, 1 << DeflateState.hash_bits(s))
    DeflateState.set_hash_mask(s, DeflateState.hash_size(s) - 1)
    DeflateState.set_hash_shift(s, (DeflateState.hash_bits(s) + MIN_MATCH - 1) / MIN_MATCH)
    DeflateState.set_window(s, Libc.malloc(DeflateState.w_size(s) * 2))
    DeflateState.set_prev(s, Libc.malloc(DeflateState.w_size(s) * 4))
    DeflateState.set_head(s, Libc.malloc(DeflateState.hash_size(s) * 4))
    DeflateState.set_high_water(s, 0)
    DeflateState.set_lit_bufsize(s, 1 << (mem_level + 6))
    DeflateState.set_pending_buf(s, Libc.malloc(DeflateState.lit_bufsize(s) * 4))
    DeflateState.set_pending_buf_size(s, DeflateState.lit_bufsize(s) * 4)
    if DeflateState.window(s) == 0 || DeflateState.prev(s) == 0 || DeflateState.head(s) == 0 || DeflateState.pending_buf(s) == 0
      DeflateState.set_status(s, DEF_FINISH_STATE)
      ZStream.set_msg(strm, zr_zlib_error_text(Z_MEM_ERROR))
      zr_deflate_end(strm)
      return Z_MEM_ERROR
    end
    DeflateState.set_sym_buf(s, DeflateState.pending_buf(s) + DeflateState.lit_bufsize(s))
    DeflateState.set_sym_end(s, (DeflateState.lit_bufsize(s) - 1) * 3)
    DeflateState.set_level(s, level)
    DeflateState.set_strategy(s, strategy)
    zr_deflate_reset(strm)
  end

  # deflateSetDictionary: puts the dictionary into the window and the
  # hash chains, before any input.
  sig [Ptr, Ptr, Word] => Word
  def zr_deflate_set_dictionary(strm, dictionary, dict_length)
    if zr_deflate_state_check(strm) != 0 || dictionary == 0
      return Z_STREAM_ERROR
    end
    s = ZStream.state(strm)
    wrap = DeflateState.wrap(s)
    if wrap == 2 || (wrap == 1 && DeflateState.status(s) != DEF_INIT_STATE) || DeflateState.lookahead(s) != 0
      return Z_STREAM_ERROR
    end
    if wrap == 1
      ZStream.set_adler(strm, zr_adler32(ZStream.adler(strm), dictionary, dict_length))
    end
    DeflateState.set_wrap(s, 0)
    if dict_length >= DeflateState.w_size(s)
      if wrap == 0
        zr_deflate_clear_hash(s)
        DeflateState.set_strstart(s, 0)
        DeflateState.set_block_start(s, 0)
        DeflateState.set_insert(s, 0)
      end
      dictionary += dict_length - DeflateState.w_size(s)
      dict_length = DeflateState.w_size(s)
    end
    avail = ZStream.avail_in(strm)
    next_in = ZStream.next_in(strm)
    ZStream.set_avail_in(strm, dict_length)
    ZStream.set_next_in(strm, dictionary)
    zr_deflate_fill_window(s)
    while DeflateState.lookahead(s) >= MIN_MATCH
      str = DeflateState.strstart(s)
      n = DeflateState.lookahead(s) - (MIN_MATCH - 1)
      while n > 0
        ins_h = zr_deflate_hash(s, DeflateState.ins_h(s), zr_deflate_window_byte(s, str + MIN_MATCH - 1))
        DeflateState.set_ins_h(s, ins_h)
        zr_zlib_set_u32(DeflateState.prev(s), str & DeflateState.w_mask(s), zr_zlib_u32(DeflateState.head(s), ins_h))
        zr_zlib_set_u32(DeflateState.head(s), ins_h, str)
        str += 1
        n -= 1
      end
      DeflateState.set_strstart(s, str)
      DeflateState.set_lookahead(s, MIN_MATCH - 1)
      zr_deflate_fill_window(s)
    end
    DeflateState.set_strstart(s, DeflateState.strstart(s) + DeflateState.lookahead(s))
    DeflateState.set_block_start(s, DeflateState.strstart(s))
    DeflateState.set_insert(s, DeflateState.lookahead(s))
    DeflateState.set_lookahead(s, 0)
    DeflateState.set_match_length(s, MIN_MATCH - 1)
    DeflateState.set_prev_length(s, MIN_MATCH - 1)
    DeflateState.set_match_available(s, 0)
    ZStream.set_next_in(strm, next_in)
    ZStream.set_avail_in(strm, avail)
    DeflateState.set_wrap(s, wrap)
    Z_OK
  end

  # deflateResetKeep: resets the stream to its start, but keeps its
  # window.
  sig [Ptr] => Word
  def zr_deflate_reset_keep(strm)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    ZStream.set_total_in(strm, 0)
    ZStream.set_total_out(strm, 0)
    ZStream.set_msg(strm, 0)
    ZStream.set_data_type(strm, Z_UNKNOWN)
    s = ZStream.state(strm)
    DeflateState.set_pending(s, 0)
    DeflateState.set_pending_out(s, DeflateState.pending_buf(s))
    if DeflateState.wrap(s) < 0
      DeflateState.set_wrap(s, 0 - DeflateState.wrap(s))
    end
    if DeflateState.wrap(s) == 2
      DeflateState.set_status(s, DEF_GZIP_STATE)
      ZStream.set_adler(strm, 0)
    else
      DeflateState.set_status(s, DEF_INIT_STATE)
      ZStream.set_adler(strm, 1)
    end
    DeflateState.set_last_flush(s, 0 - 2)
    zr_tr_init(s)
    Z_OK
  end

  # lm_init: sets the matcher's state for a new stream.
  sig [Ptr] => Void
  def zr_deflate_lm_init(s)
    DeflateState.set_window_size(s, 2 * DeflateState.w_size(s))
    zr_deflate_clear_hash(s)
    level = DeflateState.level(s)
    DeflateState.set_max_lazy_match(s, zr_deflate_config(level, 1))
    DeflateState.set_good_match(s, zr_deflate_config(level, 0))
    DeflateState.set_nice_match(s, zr_deflate_config(level, 2))
    DeflateState.set_max_chain_length(s, zr_deflate_config(level, 3))
    DeflateState.set_strstart(s, 0)
    DeflateState.set_block_start(s, 0)
    DeflateState.set_lookahead(s, 0)
    DeflateState.set_insert(s, 0)
    DeflateState.set_match_length(s, MIN_MATCH - 1)
    DeflateState.set_prev_length(s, MIN_MATCH - 1)
    DeflateState.set_match_available(s, 0)
    DeflateState.set_ins_h(s, 0)
  end

  # deflateReset
  sig [Ptr] => Word
  def zr_deflate_reset(strm)
    ret = zr_deflate_reset_keep(strm)
    if ret == Z_OK
      zr_deflate_lm_init(ZStream.state(strm))
    end
    ret
  end

  # deflateParams: sets a new level and strategy during a stream. It
  # first flushes the data that the old settings compressed.
  sig [Ptr, Word, Word] => Word
  def zr_deflate_params(strm, level, strategy)
    if zr_deflate_state_check(strm) != 0
      return Z_STREAM_ERROR
    end
    s = ZStream.state(strm)
    if level == Z_DEFAULT_COMPRESSION
      level = 6
    end
    if level < 0 || level > 9 || strategy < 0 || strategy > Z_FIXED
      return Z_STREAM_ERROR
    end
    kind = zr_deflate_kind(DeflateState.level(s))
    if (strategy != DeflateState.strategy(s) || kind != zr_deflate_kind(level)) && DeflateState.last_flush(s) != 0 - 2
      err = zr_deflate(strm, Z_BLOCK)
      if err == Z_STREAM_ERROR
        return err
      end
      if ZStream.avail_in(strm) != 0 || (DeflateState.strstart(s) - DeflateState.block_start(s)) + DeflateState.lookahead(s) != 0
        return Z_BUF_ERROR
      end
    end
    if DeflateState.level(s) != level
      if DeflateState.level(s) == 0 && DeflateState.matches(s) != 0
        if DeflateState.matches(s) == 1
          zr_deflate_slide_hash(s)
        else
          zr_deflate_clear_hash(s)
        end
        DeflateState.set_matches(s, 0)
      end
      DeflateState.set_level(s, level)
      DeflateState.set_max_lazy_match(s, zr_deflate_config(level, 1))
      DeflateState.set_good_match(s, zr_deflate_config(level, 0))
      DeflateState.set_nice_match(s, zr_deflate_config(level, 2))
      DeflateState.set_max_chain_length(s, zr_deflate_config(level, 3))
    end
    DeflateState.set_strategy(s, strategy)
    Z_OK
  end

  # putShortMSB: adds a 16-bit word to the pending output, high byte
  # first.
  sig [Ptr, Word] => Void
  def zr_deflate_put_short_msb(s, b)
    zr_tr_put_byte(s, (b >> 8) & 255)
    zr_tr_put_byte(s, b & 255)
  end

  # flush_pending: writes as much of the pending output as the stream's
  # output buffer can take.
  sig [Ptr] => Void
  def zr_deflate_flush_pending(strm)
    s = ZStream.state(strm)
    zr_tr_flush_bits(s)
    len = DeflateState.pending(s)
    if len > ZStream.avail_out(strm)
      len = ZStream.avail_out(strm)
    end
    if len == 0
      return
    end
    Libc.memmove(ZStream.next_out(strm), DeflateState.pending_out(s), len)
    ZStream.set_next_out(strm, ZStream.next_out(strm) + len)
    DeflateState.set_pending_out(s, DeflateState.pending_out(s) + len)
    ZStream.set_total_out(strm, ZStream.total_out(strm) + len)
    ZStream.set_avail_out(strm, ZStream.avail_out(strm) - len)
    DeflateState.set_pending(s, DeflateState.pending(s) - len)
    if DeflateState.pending(s) == 0
      DeflateState.set_pending_out(s, DeflateState.pending_buf(s))
    end
  end

  # ERR_RETURN: sets the error's text on the stream and returns the error.
  sig [Ptr, Word] => Word
  def zr_deflate_err(strm, err)
    ZStream.set_msg(strm, zr_zlib_error_text(err))
    err
  end

  # deflate: compresses as much of the input as the output buffer allows.
  # It writes the header first, and the trailer after a finish.
  sig [Ptr, Word] => Word
  def zr_deflate(strm, flush)
    if zr_deflate_state_check(strm) != 0 || flush > Z_BLOCK || flush < 0
      return Z_STREAM_ERROR
    end
    s = ZStream.state(strm)
    if ZStream.next_out(strm) == 0 || (ZStream.avail_in(strm) != 0 && ZStream.next_in(strm) == 0) || (DeflateState.status(s) == DEF_FINISH_STATE && flush != Z_FINISH)
      return zr_deflate_err(strm, Z_STREAM_ERROR)
    end
    if ZStream.avail_out(strm) == 0
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    old_flush = DeflateState.last_flush(s)
    DeflateState.set_last_flush(s, flush)
    if DeflateState.pending(s) != 0
      zr_deflate_flush_pending(strm)
      if ZStream.avail_out(strm) == 0
        DeflateState.set_last_flush(s, 0 - 1)
        return Z_OK
      end
    elsif ZStream.avail_in(strm) == 0 && zr_deflate_rank(flush) <= zr_deflate_rank(old_flush) && flush != Z_FINISH
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    if DeflateState.status(s) == DEF_FINISH_STATE && ZStream.avail_in(strm) != 0
      return zr_deflate_err(strm, Z_BUF_ERROR)
    end
    if DeflateState.status(s) == DEF_INIT_STATE && DeflateState.wrap(s) == 0
      DeflateState.set_status(s, DEF_BUSY_STATE)
    end
    if DeflateState.status(s) == DEF_INIT_STATE
      header = (Z_DEFLATED + ((DeflateState.w_bits(s) - 8) << 4)) << 8
      level_flags = 3
      if DeflateState.strategy(s) >= Z_HUFFMAN_ONLY || DeflateState.level(s) < 2
        level_flags = 0
      elsif DeflateState.level(s) < 6
        level_flags = 1
      elsif DeflateState.level(s) == 6
        level_flags = 2
      end
      header = header | (level_flags << 6)
      if DeflateState.strstart(s) != 0
        header = header | DEF_PRESET_DICT
      end
      header += 31 - (header % 31)
      zr_deflate_put_short_msb(s, header)
      if DeflateState.strstart(s) != 0
        zr_deflate_put_short_msb(s, (ZStream.adler(strm) >> 16) & 65535)
        zr_deflate_put_short_msb(s, ZStream.adler(strm) & 65535)
      end
      ZStream.set_adler(strm, 1)
      DeflateState.set_status(s, DEF_BUSY_STATE)
      zr_deflate_flush_pending(strm)
      if DeflateState.pending(s) != 0
        DeflateState.set_last_flush(s, 0 - 1)
        return Z_OK
      end
    end
    if DeflateState.status(s) == DEF_GZIP_STATE
      ZStream.set_adler(strm, 0)
      zr_tr_put_byte(s, 31)
      zr_tr_put_byte(s, 139)
      zr_tr_put_byte(s, 8)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      zr_tr_put_byte(s, 0)
      xfl = 0
      if DeflateState.level(s) == 9
        xfl = 2
      elsif DeflateState.strategy(s) >= Z_HUFFMAN_ONLY || DeflateState.level(s) < 2
        xfl = 4
      end
      zr_tr_put_byte(s, xfl)
      zr_tr_put_byte(s, zr_zlib_os_code())
      DeflateState.set_status(s, DEF_BUSY_STATE)
      zr_deflate_flush_pending(strm)
      if DeflateState.pending(s) != 0
        DeflateState.set_last_flush(s, 0 - 1)
        return Z_OK
      end
    end
    if ZStream.avail_in(strm) != 0 || DeflateState.lookahead(s) != 0 || (flush != Z_NO_FLUSH && DeflateState.status(s) != DEF_FINISH_STATE)
      bstate = DEF_NEED_MORE
      if DeflateState.level(s) == 0
        bstate = zr_deflate_stored(s, flush)
      elsif DeflateState.strategy(s) == Z_HUFFMAN_ONLY
        bstate = zr_deflate_huff(s, flush)
      elsif DeflateState.strategy(s) == Z_RLE
        bstate = zr_deflate_rle(s, flush)
      elsif zr_deflate_kind(DeflateState.level(s)) == DEF_KIND_FAST
        bstate = zr_deflate_fast(s, flush)
      else
        bstate = zr_deflate_slow(s, flush)
      end
      if bstate == DEF_FINISH_STARTED || bstate == DEF_FINISH_DONE
        DeflateState.set_status(s, DEF_FINISH_STATE)
      end
      if bstate == DEF_NEED_MORE || bstate == DEF_FINISH_STARTED
        if ZStream.avail_out(strm) == 0
          DeflateState.set_last_flush(s, 0 - 1)
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
            if DeflateState.lookahead(s) == 0
              DeflateState.set_strstart(s, 0)
              DeflateState.set_block_start(s, 0)
              DeflateState.set_insert(s, 0)
            end
          end
        end
        zr_deflate_flush_pending(strm)
        if ZStream.avail_out(strm) == 0
          DeflateState.set_last_flush(s, 0 - 1)
          return Z_OK
        end
      end
    end
    if flush != Z_FINISH
      return Z_OK
    end
    if DeflateState.wrap(s) <= 0
      return Z_STREAM_END
    end
    if DeflateState.wrap(s) == 2
      adler = ZStream.adler(strm)
      zr_tr_put_byte(s, adler & 255)
      zr_tr_put_byte(s, (adler >> 8) & 255)
      zr_tr_put_byte(s, (adler >> 16) & 255)
      zr_tr_put_byte(s, (adler >> 24) & 255)
      total_in = ZStream.total_in(strm)
      zr_tr_put_byte(s, total_in & 255)
      zr_tr_put_byte(s, (total_in >> 8) & 255)
      zr_tr_put_byte(s, (total_in >> 16) & 255)
      zr_tr_put_byte(s, (total_in >> 24) & 255)
    else
      zr_deflate_put_short_msb(s, (ZStream.adler(strm) >> 16) & 65535)
      zr_deflate_put_short_msb(s, ZStream.adler(strm) & 65535)
    end
    zr_deflate_flush_pending(strm)
    if DeflateState.wrap(s) > 0
      DeflateState.set_wrap(s, 0 - DeflateState.wrap(s))
    end
    if DeflateState.pending(s) != 0
      return Z_OK
    end
    Z_STREAM_END
  end

  # deflateCopy: makes `dest` a copy of `source`, with all its buffers.
  sig [Ptr, Ptr] => Word
  def zr_deflate_copy(dest, source)
    if zr_deflate_state_check(source) != 0 || dest == 0
      return Z_STREAM_ERROR
    end
    ss = ZStream.state(source)
    Libc.memmove(dest, source, ZStream.size)
    ds = Libc.malloc(DeflateState.size + DEF_TAIL_BYTES)
    if ds == 0
      return Z_MEM_ERROR
    end
    ZStream.set_state(dest, ds)
    Libc.memmove(ds, ss, DeflateState.size + DEF_TAIL_BYTES)
    zr_deflate_point_tail(ds)
    DeflateState.set_strm(ds, dest)
    DeflateState.set_window(ds, Libc.malloc(DeflateState.w_size(ds) * 2))
    DeflateState.set_prev(ds, Libc.malloc(DeflateState.w_size(ds) * 4))
    DeflateState.set_head(ds, Libc.malloc(DeflateState.hash_size(ds) * 4))
    DeflateState.set_pending_buf(ds, Libc.malloc(DeflateState.lit_bufsize(ds) * 4))
    if DeflateState.window(ds) == 0 || DeflateState.prev(ds) == 0 || DeflateState.head(ds) == 0 || DeflateState.pending_buf(ds) == 0
      zr_deflate_end(dest)
      return Z_MEM_ERROR
    end
    Libc.memmove(DeflateState.window(ds), DeflateState.window(ss), DeflateState.w_size(ds) * 2)
    Libc.memmove(DeflateState.prev(ds), DeflateState.prev(ss), DeflateState.w_size(ds) * 4)
    Libc.memmove(DeflateState.head(ds), DeflateState.head(ss), DeflateState.hash_size(ds) * 4)
    Libc.memmove(DeflateState.pending_buf(ds), DeflateState.pending_buf(ss), DeflateState.lit_bufsize(ds) * 4)
    DeflateState.set_pending_out(ds, DeflateState.pending_buf(ds) + (DeflateState.pending_out(ss) - DeflateState.pending_buf(ss)))
    DeflateState.set_sym_buf(ds, DeflateState.pending_buf(ds) + DeflateState.lit_bufsize(ds))
    Z_OK
  end

  # longest_match: finds the longest match for the string at strstart
  # along the hash chain from `cur_match`, at least prev_length long. It
  # writes the match start to match_start. As in the C code, the scan can
  # read past the lookahead into bytes that fill_window set to zero. The
  # lookahead limits the length, so the result does not depend on them.
  sig [Ptr, Word] => Word
  def zr_deflate_longest_match(s, cur_match)
    chain_length = DeflateState.max_chain_length(s)
    window = DeflateState.window(s)
    strstart = DeflateState.strstart(s)
    scan = window + strstart
    best_len = DeflateState.prev_length(s)
    nice_match = DeflateState.nice_match(s)
    limit = DEF_NIL
    if strstart > zr_deflate_max_dist(s)
      limit = strstart - zr_deflate_max_dist(s)
    end
    prev = DeflateState.prev(s)
    wmask = DeflateState.w_mask(s)
    strend = window + strstart + MAX_MATCH
    scan_end1 = zr_zlib_byte(scan + best_len - 1)
    scan_end = zr_zlib_byte(scan + best_len)
    if DeflateState.prev_length(s) >= DeflateState.good_match(s)
      chain_length = chain_length >> 2
    end
    if nice_match > DeflateState.lookahead(s)
      nice_match = DeflateState.lookahead(s)
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
          DeflateState.set_match_start(s, cur_match)
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
    if best_len <= DeflateState.lookahead(s)
      return best_len
    end
    DeflateState.lookahead(s)
  end

  # FLUSH_BLOCK_ONLY: writes the current block and starts a new one.
  sig [Ptr, Word] => Void
  def zr_deflate_flush_block_only(s, last)
    buf = 0
    if DeflateState.block_start(s) >= 0
      buf = DeflateState.window(s) + DeflateState.block_start(s)
    end
    zr_tr_flush_block(s, buf, DeflateState.strstart(s) - DeflateState.block_start(s), last)
    DeflateState.set_block_start(s, DeflateState.strstart(s))
    zr_deflate_flush_pending(DeflateState.strm(s))
  end

  # deflate_stored: copies the input to stored blocks. It copies directly
  # to the output when the data fits, and through the window and the
  # pending buffer when it does not.
  sig [Ptr, Word] => Word
  def zr_deflate_stored(s, flush)
    strm = DeflateState.strm(s)
    min_block = DeflateState.pending_buf_size(s) - 5
    if min_block > DeflateState.w_size(s)
      min_block = DeflateState.w_size(s)
    end
    last = 0
    used = ZStream.avail_in(strm)
    while true
      len = DEF_MAX_STORED
      have = (DeflateState.bi_valid(s) + 42) >> 3
      if ZStream.avail_out(strm) < have
        break
      end
      have = ZStream.avail_out(strm) - have
      left = DeflateState.strstart(s) - DeflateState.block_start(s)
      if len > left + ZStream.avail_in(strm)
        len = left + ZStream.avail_in(strm)
      end
      if len > have
        len = have
      end
      if len < min_block && ((len == 0 && flush != Z_FINISH) || flush == Z_NO_FLUSH || len != left + ZStream.avail_in(strm))
        break
      end
      last = 0
      if flush == Z_FINISH && len == left + ZStream.avail_in(strm)
        last = 1
      end
      zr_tr_stored_block(s, 0, 0, last)
      pending_buf = DeflateState.pending_buf(s)
      pending = DeflateState.pending(s)
      Machine.store8(pending_buf + pending - 4, 0, Machine.i8(len))
      Machine.store8(pending_buf + pending - 3, 0, Machine.i8(len >> 8))
      Machine.store8(pending_buf + pending - 2, 0, Machine.i8(len ^ ZLIB_MASK32))
      Machine.store8(pending_buf + pending - 1, 0, Machine.i8((len ^ ZLIB_MASK32) >> 8))
      zr_deflate_flush_pending(strm)
      if left != 0
        if left > len
          left = len
        end
        Libc.memmove(ZStream.next_out(strm), DeflateState.window(s) + DeflateState.block_start(s), left)
        ZStream.set_next_out(strm, ZStream.next_out(strm) + left)
        ZStream.set_avail_out(strm, ZStream.avail_out(strm) - left)
        ZStream.set_total_out(strm, ZStream.total_out(strm) + left)
        DeflateState.set_block_start(s, DeflateState.block_start(s) + left)
        len -= left
      end
      if len != 0
        zr_deflate_read_buf(strm, s, ZStream.next_out(strm), len)
        ZStream.set_next_out(strm, ZStream.next_out(strm) + len)
        ZStream.set_avail_out(strm, ZStream.avail_out(strm) - len)
        ZStream.set_total_out(strm, ZStream.total_out(strm) + len)
      end
      if last != 0
        break
      end
    end
    used -= ZStream.avail_in(strm)
    if used != 0
      w_size = DeflateState.w_size(s)
      if used >= w_size
        DeflateState.set_matches(s, 2)
        Libc.memmove(DeflateState.window(s), ZStream.next_in(strm) - w_size, w_size)
        DeflateState.set_strstart(s, w_size)
        DeflateState.set_insert(s, w_size)
      else
        if DeflateState.window_size(s) - DeflateState.strstart(s) <= used
          DeflateState.set_strstart(s, DeflateState.strstart(s) - w_size)
          Libc.memmove(DeflateState.window(s), DeflateState.window(s) + w_size, DeflateState.strstart(s))
          if DeflateState.matches(s) < 2
            DeflateState.set_matches(s, DeflateState.matches(s) + 1)
          end
          if DeflateState.insert(s) > DeflateState.strstart(s)
            DeflateState.set_insert(s, DeflateState.strstart(s))
          end
        end
        Libc.memmove(DeflateState.window(s) + DeflateState.strstart(s), ZStream.next_in(strm) - used, used)
        DeflateState.set_strstart(s, DeflateState.strstart(s) + used)
        room = w_size - DeflateState.insert(s)
        if used < room
          room = used
        end
        DeflateState.set_insert(s, DeflateState.insert(s) + room)
      end
      DeflateState.set_block_start(s, DeflateState.strstart(s))
    end
    if DeflateState.high_water(s) < DeflateState.strstart(s)
      DeflateState.set_high_water(s, DeflateState.strstart(s))
    end
    if last != 0
      return DEF_FINISH_DONE
    end
    if flush != Z_NO_FLUSH && flush != Z_FINISH && ZStream.avail_in(strm) == 0 && DeflateState.strstart(s) == DeflateState.block_start(s)
      return DEF_BLOCK_DONE
    end
    have = DeflateState.window_size(s) - DeflateState.strstart(s)
    if ZStream.avail_in(strm) > have && DeflateState.block_start(s) >= DeflateState.w_size(s)
      w_size = DeflateState.w_size(s)
      DeflateState.set_block_start(s, DeflateState.block_start(s) - w_size)
      DeflateState.set_strstart(s, DeflateState.strstart(s) - w_size)
      Libc.memmove(DeflateState.window(s), DeflateState.window(s) + w_size, DeflateState.strstart(s))
      if DeflateState.matches(s) < 2
        DeflateState.set_matches(s, DeflateState.matches(s) + 1)
      end
      have += w_size
      if DeflateState.insert(s) > DeflateState.strstart(s)
        DeflateState.set_insert(s, DeflateState.strstart(s))
      end
    end
    if have > ZStream.avail_in(strm)
      have = ZStream.avail_in(strm)
    end
    if have != 0
      zr_deflate_read_buf(strm, s, DeflateState.window(s) + DeflateState.strstart(s), have)
      DeflateState.set_strstart(s, DeflateState.strstart(s) + have)
      room = DeflateState.w_size(s) - DeflateState.insert(s)
      if have < room
        room = have
      end
      DeflateState.set_insert(s, DeflateState.insert(s) + room)
    end
    if DeflateState.high_water(s) < DeflateState.strstart(s)
      DeflateState.set_high_water(s, DeflateState.strstart(s))
    end
    have = (DeflateState.bi_valid(s) + 42) >> 3
    have = DeflateState.pending_buf_size(s) - have
    if have > DEF_MAX_STORED
      have = DEF_MAX_STORED
    end
    min_block = have
    if min_block > DeflateState.w_size(s)
      min_block = DeflateState.w_size(s)
    end
    left = DeflateState.strstart(s) - DeflateState.block_start(s)
    if left >= min_block || ((left != 0 || flush == Z_FINISH) && flush != Z_NO_FLUSH && ZStream.avail_in(strm) == 0 && left <= have)
      len = left
      if len > have
        len = have
      end
      last = 0
      if flush == Z_FINISH && ZStream.avail_in(strm) == 0 && len == left
        last = 1
      end
      zr_tr_stored_block(s, DeflateState.window(s) + DeflateState.block_start(s), len, last)
      DeflateState.set_block_start(s, DeflateState.block_start(s) + len)
      zr_deflate_flush_pending(strm)
    end
    if last != 0
      return DEF_FINISH_STARTED
    end
    DEF_NEED_MORE
  end

  # The end of a block function. Returns the value that the C FLUSH_BLOCK
  # returns when the output is full, or -1 to continue.
  sig [Ptr, Word] => Word
  def zr_deflate_flush_block(s, last)
    zr_deflate_flush_block_only(s, last)
    if ZStream.avail_out(DeflateState.strm(s)) == 0
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
  sig [Ptr, Word] => Word
  def zr_deflate_block_end(s, flush)
    if flush == Z_FINISH
      r = zr_deflate_flush_block(s, 1)
      if r >= 0
        return r
      end
      return DEF_FINISH_DONE
    end
    if DeflateState.sym_next(s) != 0
      r = zr_deflate_flush_block(s, 0)
      if r >= 0
        return r
      end
    end
    DEF_BLOCK_DONE
  end

  # deflate_fast: uses each match when it finds it, with no lazy
  # evaluation.
  sig [Ptr, Word] => Word
  def zr_deflate_fast(s, flush)
    while true
      if DeflateState.lookahead(s) < DEF_MIN_LOOKAHEAD
        zr_deflate_fill_window(s)
        if DeflateState.lookahead(s) < DEF_MIN_LOOKAHEAD && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState.lookahead(s) == 0
          break
        end
      end
      hash_head = DEF_NIL
      if DeflateState.lookahead(s) >= MIN_MATCH
        hash_head = zr_deflate_insert_string(s, DeflateState.strstart(s))
      end
      if hash_head != DEF_NIL && Machine.ptr(DeflateState.strstart(s) - hash_head) <= zr_deflate_max_dist(s)
        DeflateState.set_match_length(s, zr_deflate_longest_match(s, hash_head))
      end
      bflush = 0
      if DeflateState.match_length(s) >= MIN_MATCH
        bflush = zr_tr_tally(s, DeflateState.strstart(s) - DeflateState.match_start(s), DeflateState.match_length(s) - MIN_MATCH)
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - DeflateState.match_length(s))
        if DeflateState.match_length(s) <= DeflateState.max_lazy_match(s) && DeflateState.lookahead(s) >= MIN_MATCH
          DeflateState.set_match_length(s, DeflateState.match_length(s) - 1)
          while true
            DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
            zr_deflate_insert_string(s, DeflateState.strstart(s))
            DeflateState.set_match_length(s, DeflateState.match_length(s) - 1)
            if DeflateState.match_length(s) == 0
              break
            end
          end
          DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
        else
          DeflateState.set_strstart(s, DeflateState.strstart(s) + DeflateState.match_length(s))
          DeflateState.set_match_length(s, 0)
          ins_h = zr_deflate_window_byte(s, DeflateState.strstart(s))
          DeflateState.set_ins_h(s, zr_deflate_hash(s, ins_h, zr_deflate_window_byte(s, DeflateState.strstart(s) + 1)))
        end
      else
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState.strstart(s)))
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - 1)
        DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
      end
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    if DeflateState.strstart(s) < MIN_MATCH - 1
      DeflateState.set_insert(s, DeflateState.strstart(s))
    else
      DeflateState.set_insert(s, MIN_MATCH - 1)
    end
    zr_deflate_block_end(s, flush)
  end

  # deflate_slow: lazy evaluation. It keeps a match back in case the next
  # byte starts a longer match.
  sig [Ptr, Word] => Word
  def zr_deflate_slow(s, flush)
    while true
      if DeflateState.lookahead(s) < DEF_MIN_LOOKAHEAD
        zr_deflate_fill_window(s)
        if DeflateState.lookahead(s) < DEF_MIN_LOOKAHEAD && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState.lookahead(s) == 0
          break
        end
      end
      hash_head = DEF_NIL
      if DeflateState.lookahead(s) >= MIN_MATCH
        hash_head = zr_deflate_insert_string(s, DeflateState.strstart(s))
      end
      DeflateState.set_prev_length(s, DeflateState.match_length(s))
      DeflateState.set_prev_match(s, DeflateState.match_start(s))
      DeflateState.set_match_length(s, MIN_MATCH - 1)
      if hash_head != DEF_NIL && DeflateState.prev_length(s) < DeflateState.max_lazy_match(s) && Machine.ptr(DeflateState.strstart(s) - hash_head) <= zr_deflate_max_dist(s)
        DeflateState.set_match_length(s, zr_deflate_longest_match(s, hash_head))
        if DeflateState.match_length(s) <= 5 && (DeflateState.strategy(s) == Z_FILTERED || (DeflateState.match_length(s) == MIN_MATCH && DeflateState.strstart(s) - DeflateState.match_start(s) > DEF_TOO_FAR))
          DeflateState.set_match_length(s, MIN_MATCH - 1)
        end
      end
      if DeflateState.prev_length(s) >= MIN_MATCH && DeflateState.match_length(s) <= DeflateState.prev_length(s)
        max_insert = DeflateState.strstart(s) + DeflateState.lookahead(s) - MIN_MATCH
        bflush = zr_tr_tally(s, DeflateState.strstart(s) - 1 - DeflateState.prev_match(s), DeflateState.prev_length(s) - MIN_MATCH)
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - (DeflateState.prev_length(s) - 1))
        DeflateState.set_prev_length(s, DeflateState.prev_length(s) - 2)
        while true
          DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
          if DeflateState.strstart(s) <= max_insert
            zr_deflate_insert_string(s, DeflateState.strstart(s))
          end
          DeflateState.set_prev_length(s, DeflateState.prev_length(s) - 1)
          if DeflateState.prev_length(s) == 0
            break
          end
        end
        DeflateState.set_match_available(s, 0)
        DeflateState.set_match_length(s, MIN_MATCH - 1)
        DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
        if bflush != 0
          r = zr_deflate_flush_block(s, 0)
          if r >= 0
            return r
          end
        end
      elsif DeflateState.match_available(s) != 0
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState.strstart(s) - 1))
        if bflush != 0
          zr_deflate_flush_block_only(s, 0)
        end
        DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - 1)
        if ZStream.avail_out(DeflateState.strm(s)) == 0
          return DEF_NEED_MORE
        end
      else
        DeflateState.set_match_available(s, 1)
        DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - 1)
      end
    end
    if DeflateState.match_available(s) != 0
      zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState.strstart(s) - 1))
      DeflateState.set_match_available(s, 0)
    end
    if DeflateState.strstart(s) < MIN_MATCH - 1
      DeflateState.set_insert(s, DeflateState.strstart(s))
    else
      DeflateState.set_insert(s, MIN_MATCH - 1)
    end
    zr_deflate_block_end(s, flush)
  end

  # deflate_rle: encodes runs of one byte as matches at distance one.
  sig [Ptr, Word] => Word
  def zr_deflate_rle(s, flush)
    while true
      if DeflateState.lookahead(s) <= MAX_MATCH
        zr_deflate_fill_window(s)
        if DeflateState.lookahead(s) <= MAX_MATCH && flush == Z_NO_FLUSH
          return DEF_NEED_MORE
        end
        if DeflateState.lookahead(s) == 0
          break
        end
      end
      DeflateState.set_match_length(s, 0)
      if DeflateState.lookahead(s) >= MIN_MATCH && DeflateState.strstart(s) > 0
        window = DeflateState.window(s)
        scan = window + DeflateState.strstart(s) - 1
        prev = zr_zlib_byte(scan)
        if prev == zr_zlib_byte(scan + 1) && prev == zr_zlib_byte(scan + 2) && prev == zr_zlib_byte(scan + 3)
          scan += 3
          strend = window + DeflateState.strstart(s) + MAX_MATCH
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
          DeflateState.set_match_length(s, MAX_MATCH - (strend - scan))
          if DeflateState.match_length(s) > DeflateState.lookahead(s)
            DeflateState.set_match_length(s, DeflateState.lookahead(s))
          end
        end
      end
      bflush = 0
      if DeflateState.match_length(s) >= MIN_MATCH
        bflush = zr_tr_tally(s, 1, DeflateState.match_length(s) - MIN_MATCH)
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - DeflateState.match_length(s))
        DeflateState.set_strstart(s, DeflateState.strstart(s) + DeflateState.match_length(s))
        DeflateState.set_match_length(s, 0)
      else
        bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState.strstart(s)))
        DeflateState.set_lookahead(s, DeflateState.lookahead(s) - 1)
        DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
      end
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    DeflateState.set_insert(s, 0)
    zr_deflate_block_end(s, flush)
  end

  # deflate_huff: encodes each byte as a literal, with no matching.
  sig [Ptr, Word] => Word
  def zr_deflate_huff(s, flush)
    while true
      if DeflateState.lookahead(s) == 0
        zr_deflate_fill_window(s)
        if DeflateState.lookahead(s) == 0
          if flush == Z_NO_FLUSH
            return DEF_NEED_MORE
          end
          break
        end
      end
      DeflateState.set_match_length(s, 0)
      bflush = zr_tr_tally(s, 0, zr_deflate_window_byte(s, DeflateState.strstart(s)))
      DeflateState.set_lookahead(s, DeflateState.lookahead(s) - 1)
      DeflateState.set_strstart(s, DeflateState.strstart(s) + 1)
      if bflush != 0
        r = zr_deflate_flush_block(s, 0)
        if r >= 0
          return r
        end
      end
    end
    DeflateState.set_insert(s, 0)
    zr_deflate_block_end(s, flush)
  end
end
