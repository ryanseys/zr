module Zr::Kern
  # ruby/util.h: the digit tables and the scanners of digits.

  # Fills the tables that C reads by name: `ruby_hexdigits`, the lower
  # case hexadecimal digits and then the upper case ones, and
  # `ruby_digit36_to_number_table`, which gives each byte its value as a
  # digit of base 36 (`0`-`9`, then `a`-`z` and `A`-`Z` for 10-35), or -1.
  #: () -> void
  def zr_capi_util_init
    zr_memcpy(Machine.global(:ruby_hexdigits, 33), Machine.bytes("0123456789abcdef0123456789ABCDEF"), 32)
    table = Machine.global(:ruby_digit36_to_number_table, 256)
    b = 0
    while b < 256
      Machine.store8(table + b, 0, Machine.i8(zr_capi_digit36(b)))
      b += 1
    end
  end

  #: (word) -> word
  def zr_capi_digit36(b)
    if b >= 48 && b <= 57
      return b - 48
    end
    if b >= 97 && b <= 122
      return b - 87
    end
    if b >= 65 && b <= 90
      return b - 55
    end
    0 - 1
  end

  # ruby_scan_digits: the value of the digits of base `base` at `str`, up
  # to `len` bytes (to the NUL for a negative `len`), wrapped as an
  # unsigned long. `*retlen` gets the count of digits read, and
  # `*overflow` 1 when the value did not fit.
  #: (ptr, word, i32, ptr, ptr) -> word
  def ruby_scan_digits(str, len, base, retlen, overflow)
    Machine.gates_enter
    zr_c_entered()
    radix = Machine.ptr(Machine.sword(base))
    limit = Machine.ptr(0 - 1) / radix
    Machine.store32(overflow, 0, Machine.i32(0))
    value = Machine.ptr(0)
    at = str
    while len != 0
      d = zr_capi_digit36(Machine.u8(Machine.load8(at, 0)))
      if d < 0 || d >= Machine.sword(base)
        break
      end
      if value > limit
        Machine.store32(overflow, 0, Machine.i32(1))
      end
      product = Machine.umul_wrap(value, radix)
      value = Machine.uadd_wrap(product, Machine.ptr(d))
      if value < product
        Machine.store32(overflow, 0, Machine.i32(1))
      end
      at += 1
      len -= 1
    end
    Machine.store64(retlen, 0, at - str)
    Machine.word(value)
  end

  # ruby_strtoul: the unsigned long that the text at `str` starts with,
  # after white space and a sign, in base `base` (0 reads a `0x` or `0`
  # prefix), as util.c reads it: a minus sign negates the value, and one
  # too large gives ULONG_MAX with ERANGE. `*endptr` gets the first byte
  # after the number, or `str` when there is none.
  #: (ptr, ptr, i32) -> word
  def ruby_strtoul(str, endptr, base)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.sword(base)
    if b < 0 || b == 1 || b > 36
      zr_os_set_errno(EINVAL)
      return 0
    end
    at = str
    c = Machine.u8(Machine.load8(at, 0))
    while c == 32 || (c >= 9 && c <= 13)
      at += 1
      c = Machine.u8(Machine.load8(at, 0))
    end
    negative = c == 45
    at += 1 if c == 43 || c == 45
    found = str
    if Machine.u8(Machine.load8(at, 0)) == 48
      found = at + 1
      x = Machine.u8(Machine.load8(at, 1))
      if (b == 0 || b == 16) && (x == 120 || x == 88)
        b = 16
        at += 2
      else
        b = 8 if b == 0
        at += 1
      end
    elsif b == 0
      b = 10
    end
    counts = Machine.slot(16)
    value = ruby_scan_digits(at, 0 - 1, Machine.i32(b), counts, counts + 8)
    found = at + Machine.load64(counts, 0) if Machine.load64(counts, 0) > 0
    Machine.store64(endptr, 0, Machine.word(found)) if Machine.word(endptr) != 0
    if Machine.load32(counts + 8, 0) != 0
      zr_os_set_errno(ERANGE)
      return 0 - 1
    end
    negative ? 0 - value : value
  end

  # ruby_scan_hex: the value of the hexadecimal digits at `str`, up to
  # `len` bytes; `*retlen` gets their count.
  #: (ptr, word, ptr) -> word
  def ruby_scan_hex(str, len, retlen)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_scan_bits(str, len, retlen, 4)
  end

  # ruby_scan_oct: the same, for octal digits.
  #: (ptr, word, ptr) -> word
  def ruby_scan_oct(str, len, retlen)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_scan_bits(str, len, retlen, 3)
  end

  # The digits of base 2**bits at `str`, each shifted in, as CRuby's
  # scanners of hex and octal digits drop the bits that overflow.
  #: (ptr, word, ptr, word) -> word
  def zr_capi_scan_bits(str, len, retlen, bits)
    value = Machine.ptr(0)
    at = str
    while at - str < len
      d = zr_capi_digit36(Machine.u8(Machine.load8(at, 0)))
      if d < 0 || d >= (1 << bits)
        break
      end
      value = Machine.ushl_wrap(value, Machine.ptr(bits)) | Machine.ptr(d)
      at += 1
    end
    Machine.store64(retlen, 0, at - str)
    Machine.word(value)
  end

  # ruby_qsort: sorts `nel` records of `size` bytes at `base` with
  # `cmp(a, b, data)`, with the C library's qsort_r as ruby does, so
  # equal records end where they end in ruby (zr_os_c_qsort).
  #: (ptr, word, word, ptr, word) -> void
  def ruby_qsort(base, nel, size, cmp, data)
    Machine.gates_enter
    zr_c_entered()
    zr_os_c_qsort(base, nel, size, cmp, data)
  end
end
