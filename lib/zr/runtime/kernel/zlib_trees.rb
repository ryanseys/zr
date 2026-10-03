module Zr::Kern
  # trees.c: the Huffman trees that encode a block, and the bit output
  # that they use. A tree entry is the C ct_data as two 32-bit fields:
  # fc (freq or code), then dl (dad or len), 8 bytes for each entry.
  # Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.
  TR_MAX_BITS = 15
  TR_MAX_BL_BITS = 7
  TR_LITERALS = 256
  TR_LENGTH_CODES = 29
  TR_L_CODES = 286
  TR_D_CODES = 30
  TR_BL_CODES = 19
  TR_HEAP_SIZE = 573
  TR_END_BLOCK = 256
  TR_REP_3_6 = 16
  TR_REPZ_3_10 = 17
  TR_REPZ_11_138 = 18
  TR_BUF_SIZE = 16
  TR_STORED_BLOCK = 0
  TR_STATIC_TREES = 1
  TR_DYN_TREES = 2
  TR_SMALLEST = 1
  MIN_MATCH = 3
  MAX_MATCH = 258

  # The tree that build_tree builds.
  TR_LTREE = 0
  TR_DTREE = 1
  TR_BLTREE = 2

  #: (ptr, word) -> word
  def zr_tr_freq(tree, n)
    Machine.u32(Machine.load32(tree + (n * 8), 0))
  end

  #: (ptr, word, word) -> void
  def zr_tr_set_freq(tree, n, v)
    Machine.store32(tree + (n * 8), 0, Machine.i32(v))
  end

  #: (ptr, word) -> word
  def zr_tr_code(tree, n)
    Machine.u32(Machine.load32(tree + (n * 8), 0))
  end

  #: (ptr, word, word) -> void
  def zr_tr_set_code(tree, n, v)
    Machine.store32(tree + (n * 8), 0, Machine.i32(v))
  end

  #: (ptr, word) -> word
  def zr_tr_len(tree, n)
    Machine.u32(Machine.load32(tree + (n * 8), 4))
  end

  #: (ptr, word, word) -> void
  def zr_tr_set_len(tree, n, v)
    Machine.store32(tree + (n * 8), 4, Machine.i32(v))
  end

  #: (ptr, word) -> word
  def zr_tr_dad(tree, n)
    Machine.u32(Machine.load32(tree + (n * 8), 4))
  end

  #: (ptr, word, word) -> void
  def zr_tr_set_dad(tree, n, v)
    Machine.store32(tree + (n * 8), 4, Machine.i32(v))
  end

  # d_code: the distance code of a distance minus one.
  #: (word) -> word
  def zr_tr_d_code(dist)
    if dist < 256
      return zr_zlib_u32(zr_tr_dist_code(), dist)
    end
    zr_zlib_u32(zr_tr_dist_code(), 256 + (dist >> 7))
  end

  # put_byte: adds one byte to the pending output.
  #: (ptr, word) -> void
  def zr_tr_put_byte(s, c)
    pending = DeflateState[s].pending
    Machine.store8(DeflateState[s].pending_buf + pending, 0, Machine.i8(c))
    DeflateState[s].pending = pending + 1
  end

  # put_short: adds a 16-bit word to the pending output, low byte first.
  #: (ptr, word) -> void
  def zr_tr_put_short(s, w)
    zr_tr_put_byte(s, w & 255)
    zr_tr_put_byte(s, (w >> 8) & 255)
  end

  # bi_reverse: reverses the low `len` bits of `code`.
  #: (word, word) -> word
  def zr_tr_bi_reverse(code, len)
    res = 0
    while true
      res = res | (code & 1)
      code = code >> 1
      res = res << 1
      len -= 1
      if len <= 0
        break
      end
    end
    res >> 1
  end

  # bi_flush: writes out the bit buffer, and keeps 7 bits or fewer.
  #: (ptr) -> void
  def zr_tr_bi_flush(s)
    if DeflateState[s].bi_valid == 16
      zr_tr_put_short(s, DeflateState[s].bi_buf)
      DeflateState[s].bi_buf = 0
      DeflateState[s].bi_valid = 0
    elsif DeflateState[s].bi_valid >= 8
      zr_tr_put_byte(s, DeflateState[s].bi_buf & 255)
      DeflateState[s].bi_buf = DeflateState[s].bi_buf >> 8
      DeflateState[s].bi_valid = DeflateState[s].bi_valid - 8
    end
  end

  # bi_windup: writes out the bit buffer to a byte boundary.
  #: (ptr) -> void
  def zr_tr_bi_windup(s)
    if DeflateState[s].bi_valid > 8
      zr_tr_put_short(s, DeflateState[s].bi_buf)
    elsif DeflateState[s].bi_valid > 0
      zr_tr_put_byte(s, DeflateState[s].bi_buf & 255)
    end
    DeflateState[s].bi_buf = 0
    DeflateState[s].bi_valid = 0
  end

  # send_bits: writes `value` in `length` bits. The buffer is the C 16-bit
  # ush, so it keeps only its low 16 bits at each step.
  #: (ptr, word, word) -> void
  def zr_tr_send_bits(s, value, length)
    bi_valid = DeflateState[s].bi_valid
    value = value & 65535
    if bi_valid > TR_BUF_SIZE - length
      buf = (DeflateState[s].bi_buf | (value << bi_valid)) & 65535
      zr_tr_put_short(s, buf)
      DeflateState[s].bi_buf = (value >> (TR_BUF_SIZE - bi_valid)) & 65535
      DeflateState[s].bi_valid = bi_valid + length - TR_BUF_SIZE
    else
      DeflateState[s].bi_buf = (DeflateState[s].bi_buf | (value << bi_valid)) & 65535
      DeflateState[s].bi_valid = bi_valid + length
    end
  end

  # send_code: writes code `c` of `tree`.
  #: (ptr, word, ptr) -> void
  def zr_tr_send_code(s, c, tree)
    zr_tr_send_bits(s, zr_tr_code(tree, c), zr_tr_len(tree, c))
  end

  # gen_codes: makes the code of each entry of `tree` up to `max_code`
  # from the counts of each bit length. The codes are bit-reversed, as
  # deflate writes them.
  #: (ptr, word, ptr) -> void
  def zr_tr_gen_codes(tree, max_code, bl_count)
    next_code = Machine.slot(64)
    code = 0
    bits = 1
    while bits <= TR_MAX_BITS
      code = (code + zr_zlib_u32(bl_count, bits - 1)) << 1
      zr_zlib_set_u32(next_code, bits, code & 65535)
      bits += 1
    end
    n = 0
    while n <= max_code
      len = zr_tr_len(tree, n)
      if len != 0
        c = zr_zlib_u32(next_code, len)
        zr_zlib_set_u32(next_code, len, (c + 1) & 65535)
        zr_tr_set_code(tree, n, zr_tr_bi_reverse(c, len))
      end
      n += 1
    end
  end

  # init_block: clears the tree frequencies for a new block.
  #: (ptr) -> void
  def zr_tr_init_block(s)
    n = 0
    while n < TR_L_CODES
      zr_tr_set_freq(DeflateState[s].dyn_ltree, n, 0)
      n += 1
    end
    n = 0
    while n < TR_D_CODES
      zr_tr_set_freq(DeflateState[s].dyn_dtree, n, 0)
      n += 1
    end
    n = 0
    while n < TR_BL_CODES
      zr_tr_set_freq(DeflateState[s].bl_tree, n, 0)
      n += 1
    end
    zr_tr_set_freq(DeflateState[s].dyn_ltree, TR_END_BLOCK, 1)
    DeflateState[s].opt_len = 0
    DeflateState[s].static_len = 0
    DeflateState[s].sym_next = 0
    DeflateState[s].matches = 0
  end

  # _tr_init: sets the tree state of a new stream.
  #: (ptr) -> void
  def zr_tr_init(s)
    DeflateState[s].bi_buf = 0
    DeflateState[s].bi_valid = 0
    zr_tr_init_block(s)
  end

  # smaller: whether node `n` sorts before `m`, by frequency, then depth.
  #: (ptr, word, word, ptr) -> bool
  def zr_tr_smaller(tree, n, m, depth)
    fn = zr_tr_freq(tree, n)
    fm = zr_tr_freq(tree, m)
    fn < fm || (fn == fm && zr_zlib_byte(depth + n) <= zr_zlib_byte(depth + m))
  end

  #: (ptr, word) -> word
  def zr_tr_heap(s, i)
    zr_zlib_u32(DeflateState[s].heap, i)
  end

  #: (ptr, word, word) -> void
  def zr_tr_set_heap(s, i, v)
    zr_zlib_set_u32(DeflateState[s].heap, i, v)
  end

  # pqdownheap: restores the heap property from node `k` down.
  #: (ptr, ptr, word) -> void
  def zr_tr_pqdownheap(s, tree, k)
    depth = DeflateState[s].depth
    v = zr_tr_heap(s, k)
    j = k << 1
    while j <= DeflateState[s].heap_len
      if j < DeflateState[s].heap_len && zr_tr_smaller(tree, zr_tr_heap(s, j + 1), zr_tr_heap(s, j), depth)
        j += 1
      end
      if zr_tr_smaller(tree, v, zr_tr_heap(s, j), depth)
        break
      end
      zr_tr_set_heap(s, k, zr_tr_heap(s, j))
      k = j
      j = j << 1
    end
    zr_tr_set_heap(s, k, v)
  end

  # gen_bitlen: calculates the optimal bit length of each code of `tree`,
  # the count of each length, and the block's bit lengths with this tree
  # and with the static tree `stree`, if there is one.
  #: (ptr, ptr, word, ptr, ptr, word, word) -> void
  def zr_tr_gen_bitlen(s, tree, max_code, stree, extra, base, max_length)
    bl_count = DeflateState[s].bl_count
    bits = 0
    while bits <= TR_MAX_BITS
      zr_zlib_set_u32(bl_count, bits, 0)
      bits += 1
    end
    overflow = 0
    zr_tr_set_len(tree, zr_tr_heap(s, DeflateState[s].heap_max), 0)
    h = DeflateState[s].heap_max + 1
    while h < TR_HEAP_SIZE
      n = zr_tr_heap(s, h)
      bits = zr_tr_len(tree, zr_tr_dad(tree, n)) + 1
      if bits > max_length
        bits = max_length
        overflow += 1
      end
      zr_tr_set_len(tree, n, bits)
      if n <= max_code
        zr_zlib_set_u32(bl_count, bits, zr_zlib_u32(bl_count, bits) + 1)
        xbits = 0
        if n >= base
          xbits = zr_zlib_u32(extra, n - base)
        end
        f = zr_tr_freq(tree, n)
        DeflateState[s].opt_len = DeflateState[s].opt_len + (f * (bits + xbits))
        if stree != 0
          DeflateState[s].static_len = DeflateState[s].static_len + (f * (zr_tr_len(stree, n) + xbits))
        end
      end
      h += 1
    end
    if overflow == 0
      return
    end
    while true
      bits = max_length - 1
      while zr_zlib_u32(bl_count, bits) == 0
        bits -= 1
      end
      zr_zlib_set_u32(bl_count, bits, zr_zlib_u32(bl_count, bits) - 1)
      zr_zlib_set_u32(bl_count, bits + 1, zr_zlib_u32(bl_count, bits + 1) + 2)
      zr_zlib_set_u32(bl_count, max_length, zr_zlib_u32(bl_count, max_length) - 1)
      overflow -= 2
      if overflow <= 0
        break
      end
    end
    bits = max_length
    while bits != 0
      n = zr_zlib_u32(bl_count, bits)
      while n != 0
        h -= 1
        m = zr_tr_heap(s, h)
        if m <= max_code
          if zr_tr_len(tree, m) != bits
            DeflateState[s].opt_len = DeflateState[s].opt_len + ((bits - zr_tr_len(tree, m)) * zr_tr_freq(tree, m))
            zr_tr_set_len(tree, m, bits)
          end
          n -= 1
        end
      end
      bits -= 1
    end
  end

  # build_tree: builds the Huffman tree `which` (the literal, distance or
  # bit length tree) from its frequencies. It sets the lengths and codes,
  # keeps the largest code in the state, and updates the block's bit
  # lengths.
  #: (ptr, word) -> void
  def zr_tr_build_tree(s, which)
    tree = DeflateState[s].dyn_ltree
    stree = zr_tr_static_ltree()
    extra = zr_tr_extra_lbits()
    base = TR_LITERALS + 1
    elems = TR_L_CODES
    max_length = TR_MAX_BITS
    if which == TR_DTREE
      tree = DeflateState[s].dyn_dtree
      stree = zr_tr_static_dtree()
      extra = zr_tr_extra_dbits()
      base = 0
      elems = TR_D_CODES
    elsif which == TR_BLTREE
      tree = DeflateState[s].bl_tree
      stree = 0
      extra = zr_tr_extra_blbits()
      base = 0
      elems = TR_BL_CODES
      max_length = TR_MAX_BL_BITS
    end
    depth = DeflateState[s].depth
    max_code = 0 - 1
    DeflateState[s].heap_len = 0
    DeflateState[s].heap_max = TR_HEAP_SIZE
    n = 0
    while n < elems
      if zr_tr_freq(tree, n) != 0
        DeflateState[s].heap_len = DeflateState[s].heap_len + 1
        zr_tr_set_heap(s, DeflateState[s].heap_len, n)
        max_code = n
        Machine.store8(depth + n, 0, Machine.i8(0))
      else
        zr_tr_set_len(tree, n, 0)
      end
      n += 1
    end
    while DeflateState[s].heap_len < 2
      node = 0
      if max_code < 2
        max_code += 1
        node = max_code
      end
      DeflateState[s].heap_len = DeflateState[s].heap_len + 1
      zr_tr_set_heap(s, DeflateState[s].heap_len, node)
      zr_tr_set_freq(tree, node, 1)
      Machine.store8(depth + node, 0, Machine.i8(0))
      DeflateState[s].opt_len = DeflateState[s].opt_len - 1
      if stree != 0
        DeflateState[s].static_len = DeflateState[s].static_len - zr_tr_len(stree, node)
      end
    end
    if which == TR_LTREE
      DeflateState[s].l_max_code = max_code
    elsif which == TR_DTREE
      DeflateState[s].d_max_code = max_code
    else
      DeflateState[s].bl_max_code = max_code
    end
    n = DeflateState[s].heap_len / 2
    while n >= 1
      zr_tr_pqdownheap(s, tree, n)
      n -= 1
    end
    node = elems
    while true
      n = zr_tr_heap(s, TR_SMALLEST)
      zr_tr_set_heap(s, TR_SMALLEST, zr_tr_heap(s, DeflateState[s].heap_len))
      DeflateState[s].heap_len = DeflateState[s].heap_len - 1
      zr_tr_pqdownheap(s, tree, TR_SMALLEST)
      m = zr_tr_heap(s, TR_SMALLEST)
      DeflateState[s].heap_max = DeflateState[s].heap_max - 1
      zr_tr_set_heap(s, DeflateState[s].heap_max, n)
      DeflateState[s].heap_max = DeflateState[s].heap_max - 1
      zr_tr_set_heap(s, DeflateState[s].heap_max, m)
      zr_tr_set_freq(tree, node, zr_tr_freq(tree, n) + zr_tr_freq(tree, m))
      dn = zr_zlib_byte(depth + n)
      dm = zr_zlib_byte(depth + m)
      if dn >= dm
        Machine.store8(depth + node, 0, Machine.i8(dn + 1))
      else
        Machine.store8(depth + node, 0, Machine.i8(dm + 1))
      end
      zr_tr_set_dad(tree, n, node)
      zr_tr_set_dad(tree, m, node)
      zr_tr_set_heap(s, TR_SMALLEST, node)
      node += 1
      zr_tr_pqdownheap(s, tree, TR_SMALLEST)
      if DeflateState[s].heap_len < 2
        break
      end
    end
    DeflateState[s].heap_max = DeflateState[s].heap_max - 1
    zr_tr_set_heap(s, DeflateState[s].heap_max, zr_tr_heap(s, TR_SMALLEST))
    zr_tr_gen_bitlen(s, tree, max_code, stree, extra, base, max_length)
    zr_tr_gen_codes(tree, max_code, DeflateState[s].bl_count)
  end

  # scan_tree: counts the bit length tree frequencies from the lengths of
  # `tree`. It counts runs in the same way as the bit length codes.
  #: (ptr, ptr, word) -> void
  def zr_tr_scan_tree(s, tree, max_code)
    bl_tree = DeflateState[s].bl_tree
    prevlen = 0 - 1
    nextlen = zr_tr_len(tree, 0)
    count = 0
    max_count = 7
    min_count = 4
    if nextlen == 0
      max_count = 138
      min_count = 3
    end
    zr_tr_set_len(tree, max_code + 1, 65535)
    n = 0
    while n <= max_code
      curlen = nextlen
      nextlen = zr_tr_len(tree, n + 1)
      count += 1
      n += 1
      if count < max_count && curlen == nextlen
        # the run continues
      else
        if count < min_count
          zr_tr_set_freq(bl_tree, curlen, zr_tr_freq(bl_tree, curlen) + count)
        elsif curlen != 0
          if curlen != prevlen
            zr_tr_set_freq(bl_tree, curlen, zr_tr_freq(bl_tree, curlen) + 1)
          end
          zr_tr_set_freq(bl_tree, TR_REP_3_6, zr_tr_freq(bl_tree, TR_REP_3_6) + 1)
        elsif count <= 10
          zr_tr_set_freq(bl_tree, TR_REPZ_3_10, zr_tr_freq(bl_tree, TR_REPZ_3_10) + 1)
        else
          zr_tr_set_freq(bl_tree, TR_REPZ_11_138, zr_tr_freq(bl_tree, TR_REPZ_11_138) + 1)
        end
        count = 0
        prevlen = curlen
        if nextlen == 0
          max_count = 138
          min_count = 3
        elsif curlen == nextlen
          max_count = 6
          min_count = 3
        else
          max_count = 7
          min_count = 4
        end
      end
    end
  end

  # send_tree: writes the lengths of `tree` with the bit length codes.
  #: (ptr, ptr, word) -> void
  def zr_tr_send_tree(s, tree, max_code)
    bl_tree = DeflateState[s].bl_tree
    prevlen = 0 - 1
    nextlen = zr_tr_len(tree, 0)
    count = 0
    max_count = 7
    min_count = 4
    if nextlen == 0
      max_count = 138
      min_count = 3
    end
    n = 0
    while n <= max_code
      curlen = nextlen
      nextlen = zr_tr_len(tree, n + 1)
      count += 1
      n += 1
      if count < max_count && curlen == nextlen
        # the run continues
      else
        if count < min_count
          while count != 0
            zr_tr_send_code(s, curlen, bl_tree)
            count -= 1
          end
        elsif curlen != 0
          if curlen != prevlen
            zr_tr_send_code(s, curlen, bl_tree)
            count -= 1
          end
          zr_tr_send_code(s, TR_REP_3_6, bl_tree)
          zr_tr_send_bits(s, count - 3, 2)
        elsif count <= 10
          zr_tr_send_code(s, TR_REPZ_3_10, bl_tree)
          zr_tr_send_bits(s, count - 3, 3)
        else
          zr_tr_send_code(s, TR_REPZ_11_138, bl_tree)
          zr_tr_send_bits(s, count - 11, 7)
        end
        count = 0
        prevlen = curlen
        if nextlen == 0
          max_count = 138
          min_count = 3
        elsif curlen == nextlen
          max_count = 6
          min_count = 3
        else
          max_count = 7
          min_count = 4
        end
      end
    end
  end

  # build_bl_tree: builds the bit length tree. Returns the index in
  # bl_order of the last bit length code that is necessary to send.
  #: (ptr) -> word
  def zr_tr_build_bl_tree(s)
    zr_tr_scan_tree(s, DeflateState[s].dyn_ltree, DeflateState[s].l_max_code)
    zr_tr_scan_tree(s, DeflateState[s].dyn_dtree, DeflateState[s].d_max_code)
    zr_tr_build_tree(s, TR_BLTREE)
    order = zr_tr_bl_order()
    max_blindex = TR_BL_CODES - 1
    while max_blindex >= 3
      if zr_tr_len(DeflateState[s].bl_tree, zr_zlib_u32(order, max_blindex)) != 0
        break
      end
      max_blindex -= 1
    end
    DeflateState[s].opt_len = DeflateState[s].opt_len + (3 * (max_blindex + 1)) + 5 + 5 + 4
    max_blindex
  end

  # send_all_trees: writes the header of a dynamic block: the counts, the
  # bit length code lengths, the literal tree and the distance tree.
  #: (ptr, word, word, word) -> void
  def zr_tr_send_all_trees(s, lcodes, dcodes, blcodes)
    order = zr_tr_bl_order()
    zr_tr_send_bits(s, lcodes - 257, 5)
    zr_tr_send_bits(s, dcodes - 1, 5)
    zr_tr_send_bits(s, blcodes - 4, 4)
    rank = 0
    while rank < blcodes
      zr_tr_send_bits(s, zr_tr_len(DeflateState[s].bl_tree, zr_zlib_u32(order, rank)), 3)
      rank += 1
    end
    zr_tr_send_tree(s, DeflateState[s].dyn_ltree, lcodes - 1)
    zr_tr_send_tree(s, DeflateState[s].dyn_dtree, dcodes - 1)
  end

  # _tr_stored_block: writes a stored block of `stored_len` bytes at `buf`.
  #: (ptr, ptr, word, word) -> void
  def zr_tr_stored_block(s, buf, stored_len, last)
    zr_tr_send_bits(s, (TR_STORED_BLOCK << 1) + last, 3)
    zr_tr_bi_windup(s)
    zr_tr_put_short(s, stored_len & 65535)
    zr_tr_put_short(s, (stored_len ^ ZLIB_MASK32) & 65535)
    if stored_len != 0
      Libc.memmove(DeflateState[s].pending_buf + DeflateState[s].pending, buf, stored_len)
    end
    DeflateState[s].pending = DeflateState[s].pending + stored_len
  end

  # _tr_flush_bits
  #: (ptr) -> void
  def zr_tr_flush_bits(s)
    zr_tr_bi_flush(s)
  end

  # _tr_align: writes an empty static block, so inflate has sufficient
  # lookahead.
  #: (ptr) -> void
  def zr_tr_align(s)
    zr_tr_send_bits(s, TR_STATIC_TREES << 1, 3)
    zr_tr_send_code(s, TR_END_BLOCK, zr_tr_static_ltree())
    zr_tr_bi_flush(s)
  end

  # compress_block: writes the block's symbols with the given trees.
  #: (ptr, ptr, ptr) -> void
  def zr_tr_compress_block(s, ltree, dtree)
    sym_buf = DeflateState[s].sym_buf
    sym_next = DeflateState[s].sym_next
    length_code = zr_tr_length_code()
    extra_lbits = zr_tr_extra_lbits()
    extra_dbits = zr_tr_extra_dbits()
    base_length = zr_tr_base_length()
    base_dist = zr_tr_base_dist()
    sx = 0
    if sym_next != 0
      while true
        dist = zr_zlib_byte(sym_buf + sx)
        sx += 1
        dist += zr_zlib_byte(sym_buf + sx) << 8
        sx += 1
        lc = zr_zlib_byte(sym_buf + sx)
        sx += 1
        if dist == 0
          zr_tr_send_code(s, lc, ltree)
        else
          code = zr_zlib_u32(length_code, lc)
          zr_tr_send_code(s, code + TR_LITERALS + 1, ltree)
          extra = zr_zlib_u32(extra_lbits, code)
          if extra != 0
            lc -= zr_zlib_u32(base_length, code)
            zr_tr_send_bits(s, lc, extra)
          end
          dist -= 1
          code = zr_tr_d_code(dist)
          zr_tr_send_code(s, code, dtree)
          extra = zr_zlib_u32(extra_dbits, code)
          if extra != 0
            dist -= zr_zlib_u32(base_dist, code)
            zr_tr_send_bits(s, dist, extra)
          end
        end
        if sx >= sym_next
          break
        end
      end
    end
    zr_tr_send_code(s, TR_END_BLOCK, ltree)
  end

  # detect_data_type: Z_TEXT if the block contains no byte of the block
  # list and at least one byte of the allow list. Else Z_BINARY.
  #: (ptr) -> word
  def zr_tr_detect_data_type(s)
    ltree = DeflateState[s].dyn_ltree
    block_mask = 4093624447
    n = 0
    while n <= 31
      if (block_mask & 1) != 0 && zr_tr_freq(ltree, n) != 0
        return Z_BINARY
      end
      block_mask = block_mask >> 1
      n += 1
    end
    if zr_tr_freq(ltree, 9) != 0 || zr_tr_freq(ltree, 10) != 0 || zr_tr_freq(ltree, 13) != 0
      return Z_TEXT
    end
    n = 32
    while n < TR_LITERALS
      if zr_tr_freq(ltree, n) != 0
        return Z_TEXT
      end
      n += 1
    end
    Z_BINARY
  end

  # _tr_flush_block: writes the block in the smallest form (dynamic trees,
  # static trees, or stored), and starts a new block.
  #: (ptr, ptr, word, word) -> void
  def zr_tr_flush_block(s, buf, stored_len, last)
    opt_lenb = 0
    static_lenb = 0
    max_blindex = 0
    if DeflateState[s].level > 0
      strm = DeflateState[s].strm
      if ZStream[strm].data_type == Z_UNKNOWN
        ZStream[strm].data_type = zr_tr_detect_data_type(s)
      end
      zr_tr_build_tree(s, TR_LTREE)
      zr_tr_build_tree(s, TR_DTREE)
      max_blindex = zr_tr_build_bl_tree(s)
      opt_lenb = (DeflateState[s].opt_len + 3 + 7) >> 3
      static_lenb = (DeflateState[s].static_len + 3 + 7) >> 3
      if static_lenb <= opt_lenb || DeflateState[s].strategy == Z_FIXED
        opt_lenb = static_lenb
      end
    else
      opt_lenb = stored_len + 5
      static_lenb = opt_lenb
    end
    if stored_len + 4 <= opt_lenb && buf != 0
      zr_tr_stored_block(s, buf, stored_len, last)
    elsif static_lenb == opt_lenb
      zr_tr_send_bits(s, (TR_STATIC_TREES << 1) + last, 3)
      zr_tr_compress_block(s, zr_tr_static_ltree(), zr_tr_static_dtree())
    else
      zr_tr_send_bits(s, (TR_DYN_TREES << 1) + last, 3)
      zr_tr_send_all_trees(s, DeflateState[s].l_max_code + 1, DeflateState[s].d_max_code + 1, max_blindex + 1)
      zr_tr_compress_block(s, DeflateState[s].dyn_ltree, DeflateState[s].dyn_dtree)
    end
    zr_tr_init_block(s)
    if last != 0
      zr_tr_bi_windup(s)
    end
  end

  # _tr_tally: records a literal (dist 0) or a match for the block.
  # Returns 1 when the block is full and must be flushed.
  #: (ptr, word, word) -> word
  def zr_tr_tally(s, dist, lc)
    sym_buf = DeflateState[s].sym_buf
    sym_next = DeflateState[s].sym_next
    Machine.store8(sym_buf + sym_next, 0, Machine.i8(dist))
    Machine.store8(sym_buf + sym_next, 1, Machine.i8(dist >> 8))
    Machine.store8(sym_buf + sym_next, 2, Machine.i8(lc))
    sym_next += 3
    DeflateState[s].sym_next = sym_next
    if dist == 0
      zr_tr_set_freq(DeflateState[s].dyn_ltree, lc, zr_tr_freq(DeflateState[s].dyn_ltree, lc) + 1)
    else
      DeflateState[s].matches = DeflateState[s].matches + 1
      dist -= 1
      n = zr_zlib_u32(zr_tr_length_code(), lc) + TR_LITERALS + 1
      zr_tr_set_freq(DeflateState[s].dyn_ltree, n, zr_tr_freq(DeflateState[s].dyn_ltree, n) + 1)
      d = zr_tr_d_code(dist)
      zr_tr_set_freq(DeflateState[s].dyn_dtree, d, zr_tr_freq(DeflateState[s].dyn_dtree, d) + 1)
    end
    if sym_next == DeflateState[s].sym_end
      return 1
    end
    0
  end
end
