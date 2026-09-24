# inftrees.c: the decoding tables of a canonical Huffman code. A table
# entry is one 32-bit word, `op | bits << 8 | val << 16`, which is the
# C's code struct packed; an array of them is what inflate reads.
# Derived from zlib; the license is in runtime/kernel/zlib.rb.
INF_CODES = 0
INF_LENS = 1
INF_DISTS = 2
INF_MAXBITS = 15
INF_ENOUGH_LENS = 852
INF_ENOUGH_DISTS = 592
INF_ENOUGH = 1444

sig [Word, Word, Word] => Word
machine def zr_inf_code(op, bits, val)
  (op & 255) | ((bits & 255) << 8) | ((val & 65535) << 16)
end

sig [Word] => Word
machine def zr_inf_code_op(c)
  c & 255
end

sig [Word] => Word
machine def zr_inf_code_bits(c)
  (c >> 8) & 255
end

sig [Word] => Word
machine def zr_inf_code_val(c)
  (c >> 16) & 65535
end

# inflate_table: the tables for the code whose lengths are the `codes`
# words at `lens`, written from the table pointer the cell `table`
# holds, which moves past what was used; the cell `bits` holds the root
# table's index bits going in and coming out. `work` is room for
# `codes` words. Answers 0, -1 for a bad code, 1 when ENOUGH is not.
sig [Word, Ptr, Word, Ptr, Ptr, Ptr] => Word
machine def zr_inflate_table(type, lens, codes, table, bits, work)
  count = Machine.slot(64)
  offs = Machine.slot(64)
  len = 0
  while len <= INF_MAXBITS
    zr_zlib_set_u32(count, len, 0)
    len += 1
  end
  sym = 0
  while sym < codes
    n = zr_zlib_u32(lens, sym)
    zr_zlib_set_u32(count, n, zr_zlib_u32(count, n) + 1)
    sym += 1
  end
  root = Machine.load64(bits, 0)
  max = INF_MAXBITS
  while max >= 1
    if zr_zlib_u32(count, max) != 0
      break
    end
    max -= 1
  end
  if root > max
    root = max
  end
  if max == 0
    here = zr_inf_code(64, 1, 0)
    nxt = Machine.ptr(Machine.load64(table, 0))
    zr_zlib_set_u32(nxt, 0, here)
    zr_zlib_set_u32(nxt, 1, here)
    Machine.store64(table, 0, Machine.word(nxt + 8))
    Machine.store64(bits, 0, 1)
    return 0
  end
  min = 1
  while min < max
    if zr_zlib_u32(count, min) != 0
      break
    end
    min += 1
  end
  if root < min
    root = min
  end
  left = 1
  len = 1
  while len <= INF_MAXBITS
    left = left << 1
    left -= zr_zlib_u32(count, len)
    if left < 0
      return 0 - 1
    end
    len += 1
  end
  if left > 0 && (type == INF_CODES || max != 1)
    return 0 - 1
  end
  zr_zlib_set_u32(offs, 1, 0)
  len = 1
  while len < INF_MAXBITS
    zr_zlib_set_u32(offs, len + 1, zr_zlib_u32(offs, len) + zr_zlib_u32(count, len))
    len += 1
  end
  sym = 0
  while sym < codes
    n = zr_zlib_u32(lens, sym)
    if n != 0
      zr_zlib_set_u32(work, zr_zlib_u32(offs, n), sym)
      zr_zlib_set_u32(offs, n, zr_zlib_u32(offs, n) + 1)
    end
    sym += 1
  end
  base = work
  extra = work
  match = 20
  if type == INF_LENS
    base = zr_inflate_lbase()
    extra = zr_inflate_lext()
    match = 257
  elsif type == INF_DISTS
    base = zr_inflate_dbase()
    extra = zr_inflate_dext()
    match = 0
  end
  huff = 0
  sym = 0
  len = min
  nxt = Machine.ptr(Machine.load64(table, 0))
  curr = root
  drop = 0
  low = ZLIB_MASK32
  used = 1 << root
  mask = used - 1
  if (type == INF_LENS && used > INF_ENOUGH_LENS) || (type == INF_DISTS && used > INF_ENOUGH_DISTS)
    return 1
  end
  while true
    w = zr_zlib_u32(work, sym)
    here = 0
    if w + 1 < match
      here = zr_inf_code(0, len - drop, w)
    elsif w >= match
      here = zr_inf_code(zr_zlib_u32(extra, w - match), len - drop, zr_zlib_u32(base, w - match))
    else
      here = zr_inf_code(96, len - drop, 0)
    end
    incr = 1 << (len - drop)
    fill = 1 << curr
    min = fill
    while true
      fill -= incr
      zr_zlib_set_u32(nxt, (huff >> drop) + fill, here)
      if fill == 0
        break
      end
    end
    incr = 1 << (len - 1)
    while (huff & incr) != 0
      incr = incr >> 1
    end
    if incr != 0
      huff = (huff & (incr - 1)) + incr
    else
      huff = 0
    end
    sym += 1
    zr_zlib_set_u32(count, len, zr_zlib_u32(count, len) - 1)
    if zr_zlib_u32(count, len) == 0
      if len == max
        break
      end
      len = zr_zlib_u32(lens, zr_zlib_u32(work, sym))
    end
    if len > root && (huff & mask) != low
      if drop == 0
        drop = root
      end
      nxt += min * 4
      curr = len - drop
      left = 1 << curr
      while curr + drop < max
        left -= zr_zlib_u32(count, curr + drop)
        if left <= 0
          break
        end
        curr += 1
        left = left << 1
      end
      used += 1 << curr
      if (type == INF_LENS && used > INF_ENOUGH_LENS) || (type == INF_DISTS && used > INF_ENOUGH_DISTS)
        return 1
      end
      low = huff & mask
      root_table = Machine.ptr(Machine.load64(table, 0))
      zr_zlib_set_u32(root_table, low, zr_inf_code(curr, root, (nxt - root_table) / 4))
    end
  end
  if huff != 0
    zr_zlib_set_u32(nxt, huff, zr_inf_code(64, len - drop, 0))
  end
  Machine.store64(table, 0, Machine.load64(table, 0) + (used * 4))
  Machine.store64(bits, 0, root)
  0
end
