# musl's qsort_r: Lynn Ochs's smoothsort (MIT, 2011), as musl 1.2.6
# builds it for aarch64. Where musl is the C library, ruby's `Array#sort`
# is this routine, so a tie's order is its order: every comparison and
# every move is musl's, in musl's order, over the rows of a Sort (see
# rt/kernel/sort.rb) by index rather than by address.
#
# The two-word bit vector `p` lives in a 16-byte slot. musl reads its
# trailing zeros with rbit and clz, so a zero word has 64 of them.

sig [Word] => Word
machine def zr_smooth_ntz(x)
  if x == 0
    return 64
  end
  n = 0
  while (x & 1) == 0
    x = x >> 1
    n += 1
  end
  n
end

sig [Ptr] => Word
machine def zr_smooth_pntz(p)
  r = zr_smooth_ntz(Machine.load64(p, 0) - 1)
  if r != 0
    return r
  end
  r = 64 + zr_smooth_ntz(Machine.load64(p, 8))
  r != 64 ? r : 0
end

# shl and shr need n > 0. A shift of 64 or more moves a whole word first.
sig [Ptr, Word] => Void
machine def zr_smooth_shl(p, n)
  if n >= 64
    n -= 64
    Machine.store64(p, 8, Machine.load64(p, 0))
    Machine.store64(p, 0, 0)
  end
  if n != 0
    Machine.store64(p, 8, (Machine.load64(p, 8) << n) | (Machine.load64(p, 0) >> (64 - n)))
    Machine.store64(p, 0, Machine.load64(p, 0) << n)
  end
end

sig [Ptr, Word] => Void
machine def zr_smooth_shr(p, n)
  if n >= 64
    n -= 64
    Machine.store64(p, 0, Machine.load64(p, 8))
    Machine.store64(p, 8, 0)
  end
  if n != 0
    Machine.store64(p, 0, (Machine.load64(p, 0) >> n) | (Machine.load64(p, 8) << (64 - n)))
    Machine.store64(p, 8, Machine.load64(p, 8) >> n)
  end
end

# The rows at the `n` indices in `ar` rotated one place: each takes the
# next one's bytes, and the last takes the first's. A Sort's rows are at
# most 16 bytes.
sig [Ptr, Ptr, Word] => Void
machine def zr_smooth_cycle(st, ar, n)
  if n < 2
    return
  end
  stride = Sort.stride(st)
  tmp = Machine.slot(16)
  zr_memcpy(tmp, Sort.base(st) + (Machine.load64(ar, 0) * stride), stride)
  i = 0
  while i < n - 1
    zr_memcpy(Sort.base(st) + (Machine.load64(ar + (i * 8), 0) * stride), Sort.base(st) + (Machine.load64(ar + ((i + 1) * 8), 0) * stride), stride)
    i += 1
  end
  zr_memcpy(Sort.base(st) + (Machine.load64(ar + ((n - 1) * 8), 0) * stride), tmp, stride)
end

# A Leonardo number from `lp`, the table of them in rows.
sig [Ptr, Word] => Word
machine def zr_smooth_lp(lp, i)
  Machine.load64(lp + (i * 8), 0)
end

sig [Ptr, Word, Word, Ptr] => Void
machine def zr_smooth_sift(st, head, pshift, lp)
  ar = Machine.slot(904)
  Machine.store64(ar, 0, head)
  i = 1
  going = true
  while going && pshift > 1
    rt = head - 1
    lf = head - 1 - zr_smooth_lp(lp, pshift - 2)
    if zr_sort_cmp(st, Machine.load64(ar, 0), lf) >= 0 && zr_sort_cmp(st, Machine.load64(ar, 0), rt) >= 0
      going = false
    elsif zr_sort_cmp(st, lf, rt) >= 0
      Machine.store64(ar + (i * 8), 0, lf)
      i += 1
      head = lf
      pshift -= 1
    else
      Machine.store64(ar + (i * 8), 0, rt)
      i += 1
      head = rt
      pshift -= 2
    end
  end
  zr_smooth_cycle(st, ar, i)
end

sig [Ptr, Word, Ptr, Word, Word, Ptr] => Void
machine def zr_smooth_trinkle(st, head, pp, pshift, trusty, lp)
  p = Machine.slot(16)
  Machine.store64(p, 0, Machine.load64(pp, 0))
  Machine.store64(p, 8, Machine.load64(pp, 8))
  ar = Machine.slot(904)
  Machine.store64(ar, 0, head)
  i = 1
  going = true
  while going && (Machine.load64(p, 0) != 1 || Machine.load64(p, 8) != 0)
    stepson = head - zr_smooth_lp(lp, pshift)
    if zr_sort_cmp(st, stepson, Machine.load64(ar, 0)) <= 0
      going = false
    elsif trusty == 0 && pshift > 1 && (zr_sort_cmp(st, head - 1, stepson) >= 0 || zr_sort_cmp(st, head - 1 - zr_smooth_lp(lp, pshift - 2), stepson) >= 0)
      going = false
    else
      Machine.store64(ar + (i * 8), 0, stepson)
      i += 1
      head = stepson
      trail = zr_smooth_pntz(p)
      zr_smooth_shr(p, trail)
      pshift += trail
      trusty = 0
    end
  end
  if trusty == 0
    zr_smooth_cycle(st, ar, i)
    zr_smooth_sift(st, head, pshift, lp)
  end
end

# The `n` rows of `st` sorted.
sig [Ptr, Word] => Void
machine def zr_smoothsort(st, n)
  if n == 0
    return
  end
  lp = Machine.slot(768)
  Machine.store64(lp, 0, 1)
  Machine.store64(lp, 8, 1)
  i = 2
  Machine.store64(lp + 16, 0, 3)
  while zr_smooth_lp(lp, i) < n
    i += 1
    Machine.store64(lp + (i * 8), 0, zr_smooth_lp(lp, i - 2) + zr_smooth_lp(lp, i - 1) + 1)
  end
  p = Machine.slot(16)
  Machine.store64(p, 0, 1)
  Machine.store64(p, 8, 0)
  pshift = 1
  head = 0
  high = n - 1
  while head < high
    if (Machine.load64(p, 0) & 3) == 3
      zr_smooth_sift(st, head, pshift, lp)
      zr_smooth_shr(p, 2)
      pshift += 2
    else
      if zr_smooth_lp(lp, pshift - 1) >= high - head
        zr_smooth_trinkle(st, head, p, pshift, 0, lp)
      else
        zr_smooth_sift(st, head, pshift, lp)
      end
      if pshift == 1
        zr_smooth_shl(p, 1)
        pshift = 0
      else
        zr_smooth_shl(p, pshift - 1)
        pshift = 1
      end
    end
    Machine.store64(p, 0, Machine.load64(p, 0) | 1)
    head += 1
  end
  zr_smooth_trinkle(st, head, p, pshift, 0, lp)
  while pshift != 1 || Machine.load64(p, 0) != 1 || Machine.load64(p, 8) != 0
    if pshift <= 1
      trail = zr_smooth_pntz(p)
      zr_smooth_shr(p, trail)
      pshift += trail
    else
      zr_smooth_shl(p, 2)
      pshift -= 2
      Machine.store64(p, 0, Machine.load64(p, 0) ^ 7)
      zr_smooth_shr(p, 1)
      zr_smooth_trinkle(st, head - zr_smooth_lp(lp, pshift) - 1, p, pshift + 1, 1, lp)
      zr_smooth_shl(p, 1)
      Machine.store64(p, 0, Machine.load64(p, 0) | 1)
      zr_smooth_trinkle(st, head - 1, p, pshift, 1, lp)
    end
    head -= 1
  end
end
