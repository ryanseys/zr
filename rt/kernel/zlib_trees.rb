# trees.c: the Huffman trees a block is written with, and the bit
# output they go through. A tree entry is the C's ct_data as two 32-bit
# cells: fc (freq or code) then dl (dad or len), 8 bytes an entry.
# Derived from zlib; the license is in rt/kernel/zlib.rb.
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

# Which tree build_tree is asked for.
TR_LTREE = 0
TR_DTREE = 1
TR_BLTREE = 2

sig [Ptr, Word] => Word
machine def zr_tr_freq(tree, n)
  Machine.word(Machine.load32(tree + (n * 8), 0))
end

sig [Ptr, Word, Word] => Void
machine def zr_tr_set_freq(tree, n, v)
  Machine.store32(tree + (n * 8), 0, Machine.i32(v))
end

sig [Ptr, Word] => Word
machine def zr_tr_code(tree, n)
  Machine.word(Machine.load32(tree + (n * 8), 0))
end

sig [Ptr, Word, Word] => Void
machine def zr_tr_set_code(tree, n, v)
  Machine.store32(tree + (n * 8), 0, Machine.i32(v))
end

sig [Ptr, Word] => Word
machine def zr_tr_len(tree, n)
  Machine.word(Machine.load32(tree + (n * 8), 4))
end

sig [Ptr, Word, Word] => Void
machine def zr_tr_set_len(tree, n, v)
  Machine.store32(tree + (n * 8), 4, Machine.i32(v))
end

sig [Ptr, Word] => Word
machine def zr_tr_dad(tree, n)
  Machine.word(Machine.load32(tree + (n * 8), 4))
end

sig [Ptr, Word, Word] => Void
machine def zr_tr_set_dad(tree, n, v)
  Machine.store32(tree + (n * 8), 4, Machine.i32(v))
end

# d_code: the distance code of a distance less one.
sig [Word] => Word
machine def zr_tr_d_code(dist)
  if dist < 256
    return zr_zlib_u32(zr_tr_dist_code(), dist)
  end
  zr_zlib_u32(zr_tr_dist_code(), 256 + (dist >> 7))
end

# put_byte: one byte onto the pending output.
sig [Ptr, Word] => Void
machine def zr_tr_put_byte(s, c)
  pending = DeflateState.pending(s)
  Machine.store8(DeflateState.pending_buf(s) + pending, 0, Machine.i8(c))
  DeflateState.set_pending(s, pending + 1)
end

# put_short: a 16-bit word onto the pending output, low byte first.
sig [Ptr, Word] => Void
machine def zr_tr_put_short(s, w)
  zr_tr_put_byte(s, w & 255)
  zr_tr_put_byte(s, (w >> 8) & 255)
end

# bi_reverse: the low `len` bits of `code`, the other way round.
sig [Word, Word] => Word
machine def zr_tr_bi_reverse(code, len)
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

# bi_flush: the bit buffer written out, keeping at most 7 bits.
sig [Ptr] => Void
machine def zr_tr_bi_flush(s)
  if DeflateState.bi_valid(s) == 16
    zr_tr_put_short(s, DeflateState.bi_buf(s))
    DeflateState.set_bi_buf(s, 0)
    DeflateState.set_bi_valid(s, 0)
  elsif DeflateState.bi_valid(s) >= 8
    zr_tr_put_byte(s, DeflateState.bi_buf(s) & 255)
    DeflateState.set_bi_buf(s, DeflateState.bi_buf(s) >> 8)
    DeflateState.set_bi_valid(s, DeflateState.bi_valid(s) - 8)
  end
end

# bi_windup: the bit buffer written out to a byte boundary.
sig [Ptr] => Void
machine def zr_tr_bi_windup(s)
  if DeflateState.bi_valid(s) > 8
    zr_tr_put_short(s, DeflateState.bi_buf(s))
  elsif DeflateState.bi_valid(s) > 0
    zr_tr_put_byte(s, DeflateState.bi_buf(s) & 255)
  end
  DeflateState.set_bi_buf(s, 0)
  DeflateState.set_bi_valid(s, 0)
end

# send_bits: `value` on `length` bits. The buffer is the C's 16-bit
# ush, so it keeps its low 16 bits at every step.
sig [Ptr, Word, Word] => Void
machine def zr_tr_send_bits(s, value, length)
  bi_valid = DeflateState.bi_valid(s)
  value = value & 65535
  if bi_valid > TR_BUF_SIZE - length
    buf = (DeflateState.bi_buf(s) | (value << bi_valid)) & 65535
    zr_tr_put_short(s, buf)
    DeflateState.set_bi_buf(s, (value >> (TR_BUF_SIZE - bi_valid)) & 65535)
    DeflateState.set_bi_valid(s, bi_valid + length - TR_BUF_SIZE)
  else
    DeflateState.set_bi_buf(s, (DeflateState.bi_buf(s) | (value << bi_valid)) & 65535)
    DeflateState.set_bi_valid(s, bi_valid + length)
  end
end

# send_code: code `c` of `tree`.
sig [Ptr, Word, Ptr] => Void
machine def zr_tr_send_code(s, c, tree)
  zr_tr_send_bits(s, zr_tr_code(tree, c), zr_tr_len(tree, c))
end

# gen_codes: the code of every entry of `tree` up to `max_code` from
# the counts of each bit length, bit-reversed as deflate writes them.
sig [Ptr, Word, Ptr] => Void
machine def zr_tr_gen_codes(tree, max_code, bl_count)
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

# init_block: the trees' frequencies cleared for a new block.
sig [Ptr] => Void
machine def zr_tr_init_block(s)
  n = 0
  while n < TR_L_CODES
    zr_tr_set_freq(DeflateState.dyn_ltree(s), n, 0)
    n += 1
  end
  n = 0
  while n < TR_D_CODES
    zr_tr_set_freq(DeflateState.dyn_dtree(s), n, 0)
    n += 1
  end
  n = 0
  while n < TR_BL_CODES
    zr_tr_set_freq(DeflateState.bl_tree(s), n, 0)
    n += 1
  end
  zr_tr_set_freq(DeflateState.dyn_ltree(s), TR_END_BLOCK, 1)
  DeflateState.set_opt_len(s, 0)
  DeflateState.set_static_len(s, 0)
  DeflateState.set_sym_next(s, 0)
  DeflateState.set_matches(s, 0)
end

# _tr_init: the tree state of a new stream.
sig [Ptr] => Void
machine def zr_tr_init(s)
  DeflateState.set_bi_buf(s, 0)
  DeflateState.set_bi_valid(s, 0)
  zr_tr_init_block(s)
end

# smaller: whether node `n` sorts before `m`, by frequency, then depth.
sig [Ptr, Word, Word, Ptr] => Bool
machine def zr_tr_smaller(tree, n, m, depth)
  fn = zr_tr_freq(tree, n)
  fm = zr_tr_freq(tree, m)
  fn < fm || (fn == fm && zr_zlib_byte(depth + n) <= zr_zlib_byte(depth + m))
end

sig [Ptr, Word] => Word
machine def zr_tr_heap(s, i)
  zr_zlib_u32(DeflateState.heap(s), i)
end

sig [Ptr, Word, Word] => Void
machine def zr_tr_set_heap(s, i, v)
  zr_zlib_set_u32(DeflateState.heap(s), i, v)
end

# pqdownheap: the heap property restored from node `k` down.
sig [Ptr, Ptr, Word] => Void
machine def zr_tr_pqdownheap(s, tree, k)
  depth = DeflateState.depth(s)
  v = zr_tr_heap(s, k)
  j = k << 1
  while j <= DeflateState.heap_len(s)
    if j < DeflateState.heap_len(s) && zr_tr_smaller(tree, zr_tr_heap(s, j + 1), zr_tr_heap(s, j), depth)
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

# gen_bitlen: the optimal bit length of every code of `tree`, the
# counts of each length, and the block's bit lengths under this tree
# and under the static one, `stree`, when there is one.
sig [Ptr, Ptr, Word, Ptr, Ptr, Word, Word] => Void
machine def zr_tr_gen_bitlen(s, tree, max_code, stree, extra, base, max_length)
  bl_count = DeflateState.bl_count(s)
  bits = 0
  while bits <= TR_MAX_BITS
    zr_zlib_set_u32(bl_count, bits, 0)
    bits += 1
  end
  overflow = 0
  zr_tr_set_len(tree, zr_tr_heap(s, DeflateState.heap_max(s)), 0)
  h = DeflateState.heap_max(s) + 1
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
      DeflateState.set_opt_len(s, DeflateState.opt_len(s) + (f * (bits + xbits)))
      if stree != 0
        DeflateState.set_static_len(s, DeflateState.static_len(s) + (f * (zr_tr_len(stree, n) + xbits)))
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
          DeflateState.set_opt_len(s, DeflateState.opt_len(s) + ((bits - zr_tr_len(tree, m)) * zr_tr_freq(tree, m)))
          zr_tr_set_len(tree, m, bits)
        end
        n -= 1
      end
    end
    bits -= 1
  end
end

# build_tree: the Huffman tree `which` (the literal, distance or bit
# length tree) built from its frequencies: its lengths and codes, its
# largest code kept on the state, and the block's bit lengths updated.
sig [Ptr, Word] => Void
machine def zr_tr_build_tree(s, which)
  tree = DeflateState.dyn_ltree(s)
  stree = zr_tr_static_ltree()
  extra = zr_tr_extra_lbits()
  base = TR_LITERALS + 1
  elems = TR_L_CODES
  max_length = TR_MAX_BITS
  if which == TR_DTREE
    tree = DeflateState.dyn_dtree(s)
    stree = zr_tr_static_dtree()
    extra = zr_tr_extra_dbits()
    base = 0
    elems = TR_D_CODES
  elsif which == TR_BLTREE
    tree = DeflateState.bl_tree(s)
    stree = 0
    extra = zr_tr_extra_blbits()
    base = 0
    elems = TR_BL_CODES
    max_length = TR_MAX_BL_BITS
  end
  depth = DeflateState.depth(s)
  max_code = 0 - 1
  DeflateState.set_heap_len(s, 0)
  DeflateState.set_heap_max(s, TR_HEAP_SIZE)
  n = 0
  while n < elems
    if zr_tr_freq(tree, n) != 0
      DeflateState.set_heap_len(s, DeflateState.heap_len(s) + 1)
      zr_tr_set_heap(s, DeflateState.heap_len(s), n)
      max_code = n
      Machine.store8(depth + n, 0, Machine.i8(0))
    else
      zr_tr_set_len(tree, n, 0)
    end
    n += 1
  end
  while DeflateState.heap_len(s) < 2
    node = 0
    if max_code < 2
      max_code += 1
      node = max_code
    end
    DeflateState.set_heap_len(s, DeflateState.heap_len(s) + 1)
    zr_tr_set_heap(s, DeflateState.heap_len(s), node)
    zr_tr_set_freq(tree, node, 1)
    Machine.store8(depth + node, 0, Machine.i8(0))
    DeflateState.set_opt_len(s, DeflateState.opt_len(s) - 1)
    if stree != 0
      DeflateState.set_static_len(s, DeflateState.static_len(s) - zr_tr_len(stree, node))
    end
  end
  if which == TR_LTREE
    DeflateState.set_l_max_code(s, max_code)
  elsif which == TR_DTREE
    DeflateState.set_d_max_code(s, max_code)
  else
    DeflateState.set_bl_max_code(s, max_code)
  end
  n = DeflateState.heap_len(s) / 2
  while n >= 1
    zr_tr_pqdownheap(s, tree, n)
    n -= 1
  end
  node = elems
  while true
    n = zr_tr_heap(s, TR_SMALLEST)
    zr_tr_set_heap(s, TR_SMALLEST, zr_tr_heap(s, DeflateState.heap_len(s)))
    DeflateState.set_heap_len(s, DeflateState.heap_len(s) - 1)
    zr_tr_pqdownheap(s, tree, TR_SMALLEST)
    m = zr_tr_heap(s, TR_SMALLEST)
    DeflateState.set_heap_max(s, DeflateState.heap_max(s) - 1)
    zr_tr_set_heap(s, DeflateState.heap_max(s), n)
    DeflateState.set_heap_max(s, DeflateState.heap_max(s) - 1)
    zr_tr_set_heap(s, DeflateState.heap_max(s), m)
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
    if DeflateState.heap_len(s) < 2
      break
    end
  end
  DeflateState.set_heap_max(s, DeflateState.heap_max(s) - 1)
  zr_tr_set_heap(s, DeflateState.heap_max(s), zr_tr_heap(s, TR_SMALLEST))
  zr_tr_gen_bitlen(s, tree, max_code, stree, extra, base, max_length)
  zr_tr_gen_codes(tree, max_code, DeflateState.bl_count(s))
end

# scan_tree: the bit length tree's frequencies from the lengths of
# `tree`, counting runs as the bit length codes will.
sig [Ptr, Ptr, Word] => Void
machine def zr_tr_scan_tree(s, tree, max_code)
  bl_tree = DeflateState.bl_tree(s)
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
      # the run goes on
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

# send_tree: the lengths of `tree` written with the bit length codes.
sig [Ptr, Ptr, Word] => Void
machine def zr_tr_send_tree(s, tree, max_code)
  bl_tree = DeflateState.bl_tree(s)
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
      # the run goes on
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

# build_bl_tree: the bit length tree built, and the index in bl_order
# of the last bit length code worth sending.
sig [Ptr] => Word
machine def zr_tr_build_bl_tree(s)
  zr_tr_scan_tree(s, DeflateState.dyn_ltree(s), DeflateState.l_max_code(s))
  zr_tr_scan_tree(s, DeflateState.dyn_dtree(s), DeflateState.d_max_code(s))
  zr_tr_build_tree(s, TR_BLTREE)
  order = zr_tr_bl_order()
  max_blindex = TR_BL_CODES - 1
  while max_blindex >= 3
    if zr_tr_len(DeflateState.bl_tree(s), zr_zlib_u32(order, max_blindex)) != 0
      break
    end
    max_blindex -= 1
  end
  DeflateState.set_opt_len(s, DeflateState.opt_len(s) + (3 * (max_blindex + 1)) + 5 + 5 + 4)
  max_blindex
end

# send_all_trees: a dynamic block's header: the counts, the bit length
# code lengths, the literal tree and the distance tree.
sig [Ptr, Word, Word, Word] => Void
machine def zr_tr_send_all_trees(s, lcodes, dcodes, blcodes)
  order = zr_tr_bl_order()
  zr_tr_send_bits(s, lcodes - 257, 5)
  zr_tr_send_bits(s, dcodes - 1, 5)
  zr_tr_send_bits(s, blcodes - 4, 4)
  rank = 0
  while rank < blcodes
    zr_tr_send_bits(s, zr_tr_len(DeflateState.bl_tree(s), zr_zlib_u32(order, rank)), 3)
    rank += 1
  end
  zr_tr_send_tree(s, DeflateState.dyn_ltree(s), lcodes - 1)
  zr_tr_send_tree(s, DeflateState.dyn_dtree(s), dcodes - 1)
end

# _tr_stored_block: a stored block of `stored_len` bytes at `buf`.
sig [Ptr, Ptr, Word, Word] => Void
machine def zr_tr_stored_block(s, buf, stored_len, last)
  zr_tr_send_bits(s, (TR_STORED_BLOCK << 1) + last, 3)
  zr_tr_bi_windup(s)
  zr_tr_put_short(s, stored_len & 65535)
  zr_tr_put_short(s, (stored_len ^ ZLIB_MASK32) & 65535)
  if stored_len != 0
    memmove(DeflateState.pending_buf(s) + DeflateState.pending(s), buf, stored_len)
  end
  DeflateState.set_pending(s, DeflateState.pending(s) + stored_len)
end

# _tr_flush_bits
sig [Ptr] => Void
machine def zr_tr_flush_bits(s)
  zr_tr_bi_flush(s)
end

# _tr_align: an empty static block, so inflate has enough lookahead.
sig [Ptr] => Void
machine def zr_tr_align(s)
  zr_tr_send_bits(s, TR_STATIC_TREES << 1, 3)
  zr_tr_send_code(s, TR_END_BLOCK, zr_tr_static_ltree())
  zr_tr_bi_flush(s)
end

# compress_block: the block's symbols written with the given trees.
sig [Ptr, Ptr, Ptr] => Void
machine def zr_tr_compress_block(s, ltree, dtree)
  sym_buf = DeflateState.sym_buf(s)
  sym_next = DeflateState.sym_next(s)
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

# detect_data_type: Z_TEXT when the block holds no byte of the block
# list and one of the allow list, Z_BINARY otherwise.
sig [Ptr] => Word
machine def zr_tr_detect_data_type(s)
  ltree = DeflateState.dyn_ltree(s)
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

# _tr_flush_block: the block written the cheapest way, with dynamic
# trees, static trees or stored, and a new block begun.
sig [Ptr, Ptr, Word, Word] => Void
machine def zr_tr_flush_block(s, buf, stored_len, last)
  opt_lenb = 0
  static_lenb = 0
  max_blindex = 0
  if DeflateState.level(s) > 0
    strm = DeflateState.strm(s)
    if ZStream.data_type(strm) == Z_UNKNOWN
      ZStream.set_data_type(strm, zr_tr_detect_data_type(s))
    end
    zr_tr_build_tree(s, TR_LTREE)
    zr_tr_build_tree(s, TR_DTREE)
    max_blindex = zr_tr_build_bl_tree(s)
    opt_lenb = (DeflateState.opt_len(s) + 3 + 7) >> 3
    static_lenb = (DeflateState.static_len(s) + 3 + 7) >> 3
    if static_lenb <= opt_lenb || DeflateState.strategy(s) == Z_FIXED
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
    zr_tr_send_all_trees(s, DeflateState.l_max_code(s) + 1, DeflateState.d_max_code(s) + 1, max_blindex + 1)
    zr_tr_compress_block(s, DeflateState.dyn_ltree(s), DeflateState.dyn_dtree(s))
  end
  zr_tr_init_block(s)
  if last != 0
    zr_tr_bi_windup(s)
  end
end

# _tr_tally: a literal (dist 0) or a match kept for the block; 1 when
# the block is full and must be flushed.
sig [Ptr, Word, Word] => Word
machine def zr_tr_tally(s, dist, lc)
  sym_buf = DeflateState.sym_buf(s)
  sym_next = DeflateState.sym_next(s)
  Machine.store8(sym_buf + sym_next, 0, Machine.i8(dist))
  Machine.store8(sym_buf + sym_next, 1, Machine.i8(dist >> 8))
  Machine.store8(sym_buf + sym_next, 2, Machine.i8(lc))
  sym_next += 3
  DeflateState.set_sym_next(s, sym_next)
  if dist == 0
    zr_tr_set_freq(DeflateState.dyn_ltree(s), lc, zr_tr_freq(DeflateState.dyn_ltree(s), lc) + 1)
  else
    DeflateState.set_matches(s, DeflateState.matches(s) + 1)
    dist -= 1
    n = zr_zlib_u32(zr_tr_length_code(), lc) + TR_LITERALS + 1
    zr_tr_set_freq(DeflateState.dyn_ltree(s), n, zr_tr_freq(DeflateState.dyn_ltree(s), n) + 1)
    d = zr_tr_d_code(dist)
    zr_tr_set_freq(DeflateState.dyn_dtree(s), d, zr_tr_freq(DeflateState.dyn_dtree(s), d) + 1)
  end
  if sym_next == DeflateState.sym_end(s)
    return 1
  end
  0
end
