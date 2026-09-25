# Float: a double, stored as a flonum (CRuby's rotation, when the
# exponent fits) or in a heap cell. This file has the shortest
# round-trip digits (Ryu), CRuby's to_s layout, and the arithmetic and
# comparisons, also with Integer operands.
Machine.import "fmod", [F64, F64] => F64
Machine.import "pow", [F64, F64] => F64

Machine.struct :RFloat, basic: RBasic, bits: Word
T_FLOAT = 4
G_FLOAT = 40
FLONUM_ZERO = 9223372036854775810
INF_BITS = 9218868437227405312
# The gates of the Float operators that compiled code inlines for
# flonums (`float_path` in the lowering). The Integer gates are in
# runtime/kernel/integer.rb.
GATE_FLO_PLUS = 4194304
GATE_FLO_MINUS = 8388608
GATE_FLO_MUL = 16777216
GATE_FLO_DIV = 33554432
GATE_FLO_LT = 67108864
GATE_FLO_LE = 134217728
GATE_FLO_GT = 268435456
GATE_FLO_GE = 536870912
GATE_FLO_EQ = 1073741824

sig [Value] => Bool
machine def zr_flonum_p(v)
  (Machine.word(v) & 3) == 2
end

sig [Value] => Bool
machine def zr_float_p(v)
  zr_flonum_p(v) || (!zr_special_p(v) && zr_type(v) == T_FLOAT)
end

sig [Value] => Value
machine def zr_float_p_m(v)
  zr_bool(zr_float_p(v))
end

# Whether `v` is an Integer: a fixnum or a bignum.
sig [Value] => Value
machine def zr_integer_p_m(v)
  zr_bool(zr_fixnum_p(v) || zr_big_p(v))
end

# Makes a Float from a double: a flonum when the top bits of the
# exponent are 011 or 100, the flonum zero for +0.0, else a heap cell.
sig [F64] => Value
machine def zr_float_new(d)
  b = Machine.ptr(Machine.bits(d))
  top = (b >> 60) & 7
  if b != 3458764513820540928 && (top == 3 || top == 4)
    rotated = (b << 3) | (b >> 61)
    return Machine.value((rotated & 18446744073709551614) | 2)
  end
  if b == 0
    return Machine.value(FLONUM_ZERO)
  end
  f = zr_alloc(T_FLOAT, zr_global(G_FLOAT), RFloat.size)
  RFloat.set_bits(f, Machine.word(b))
  RBasic.set_flags(f, RBasic.flags(f) | FL_FREEZE)
  f
end

sig [Value] => F64
machine def zr_float_value(v)
  if zr_flonum_p(v)
    if Machine.word(v) == FLONUM_ZERO
      return Machine.f64(0)
    end
    w = Machine.ptr(v)
    b63 = w >> 63
    x = (2 - b63) | (w & 18446744073709551612)
    return Machine.f64((x >> 3) | (x << 61))
  end
  Machine.f64(RFloat.bits(v))
end

# Converts a Float or Integer operand to a double. For all other values
# it raises a TypeError and returns undef (it does not call `coerce`).
sig [Value, Value, Ptr, Word, Word] => Value
machine def zr_float_operand(recv, v, out, mid, kind)
  if zr_fixnum_p(v)
    Machine.store64(out, 0, Machine.bits(Machine.to_f64(zr_fix2long(v))))
    return Machine.value(QNIL)
  end
  if zr_float_p(v)
    Machine.store64(out, 0, Machine.bits(zr_float_value(v)))
    return Machine.value(QNIL)
  end
  if zr_big_p(v)
    # Arithmetic with a bignum uses its nearest double.
    f = zr_send(v, Machine.id(:to_f), 0, 0)
    return f if f == QUNDEF
    Machine.store64(out, 0, Machine.bits(zr_float_value(f)))
    return Machine.value(QNIL)
  end
  zr_num_coerce(recv, v, mid, kind)
end

sig [F64] => Bool
machine def zr_nan_p(d)
  d != d
end

sig [F64] => Bool
machine def zr_inf_p(d)
  Machine.fabs(d) == Machine.f64(INF_BITS)
end

# --- arithmetic -------------------------------------------------------

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_plus(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:+), 0)
  return r if r != QNIL
  zr_float_new(zr_float_value(recv) + Machine.f64(Machine.load64(out, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_minus(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:-), 0)
  return r if r != QNIL
  zr_float_new(zr_float_value(recv) - Machine.f64(Machine.load64(out, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_mul(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:*), 0)
  return r if r != QNIL
  zr_float_new(zr_float_value(recv) * Machine.f64(Machine.load64(out, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_div(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:/), 0)
  return r if r != QNIL
  zr_float_new(zr_float_value(recv) / Machine.f64(Machine.load64(out, 0)))
end

# CRuby's flodivmod: the modulo takes the divisor's sign.
sig [F64, F64] => F64
machine def zr_float_mod(x, y)
  if zr_nan_p(y)
    return y
  end
  if x == Machine.f64(0) || (zr_inf_p(y) && !zr_inf_p(x))
    m = x
  else
    m = fmod(x, y)
  end
  if y * m < Machine.f64(0)
    m = m + y
  end
  m
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_mod(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:%), 0)
  return r if r != QNIL
  y = Machine.f64(Machine.load64(out, 0))
  if y == Machine.f64(0)
    return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12)
  end
  zr_float_new(zr_float_mod(zr_float_value(recv), y))
end

# The quotient that CRuby's divmod returns: rounded, and one less when
# the modulo changed sign.
sig [F64, F64] => F64
machine def zr_float_quotient(x, y)
  if zr_nan_p(y)
    return y
  end
  if x == Machine.f64(0) || (zr_inf_p(y) && !zr_inf_p(x))
    m = x
  else
    m = fmod(x, y)
  end
  if zr_inf_p(x) && !zr_inf_p(y)
    d = x
  else
    d = Machine.nearest((x - m) / y)
  end
  if y * m < Machine.f64(0)
    d = d - Machine.f64(4607182418800017408)
  end
  d
end

# CRuby's rb_dbl_complex_new_polar_pi: the Complex at the angle `ang`
# times pi. It is exact on the axes, and else uses cospi and sinpi.
sig [F64, F64] => Value
machine def zr_complex_polar_pi(abs, ang)
  whole = Machine.trunc(ang)
  fr = ang - whole
  pair = Machine.slot(16)
  half_turn = Machine.f64(4602678819172646912)
  if fr == half_turn || fr == Machine.f64(0) - half_turn
    # An odd number of quarter turns is on the imaginary axis.
    half = whole / Machine.f64(4611686018427387904)
    odd = (half - Machine.trunc(half)) != Machine.f64(0)
    if odd == (fr > Machine.f64(0))
      abs = Machine.f64(0) - abs
    end
    Machine.store64(pair, 0, Machine.word(zr_float_new(Machine.f64(0))))
    Machine.store64(pair, 8, Machine.word(zr_float_new(abs)))
  else
    Machine.store64(pair, 0, Machine.word(zr_float_new(abs * zr_os_cospi(ang))))
    Machine.store64(pair, 8, Machine.word(zr_float_new(abs * zr_os_sinpi(ang))))
  end
  zr_send(zr_core_class(Machine.id(:Complex)), Machine.id(:rectangular), 2, pair)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_pow(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:**), 0)
  return r if r != QNIL
  x = zr_float_value(recv)
  y = Machine.f64(Machine.load64(out, 0))
  if x < Machine.f64(0) && y != Machine.nearest(y)
    return zr_complex_polar_pi(pow(Machine.f64(0) - x, y), y)
  end
  zr_float_new(pow(x, y))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_uminus(recv, argc, argv, cref, blk)
  zr_float_new(-zr_float_value(recv))
end

# --- comparison -------------------------------------------------------

# Returns -1, 0, 1, or 2 when one side is NaN.
sig [F64, F64] => Word
machine def zr_float_cmp(a, b)
  if a < b
    return 0 - 1
  end
  if a > b
    return 1
  end
  if a == b
    return 0
  end
  2
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_fixnum_p(other) || zr_float_p(other) || zr_big_p(other)
    return zr_bool(zr_float_cmp_value(recv, other) == 0)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  zr_send(other, Machine.id(:==), 1, slot)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_cmp(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if !zr_fixnum_p(other) && !zr_float_p(other) && !zr_big_p(other)
    return zr_num_coerce(recv, other, Machine.id(:<=>), 2)
  end
  c = zr_float_cmp_value(recv, other)
  if c == 2
    return Machine.value(QNIL)
  end
  zr_fix(c)
end

# `recv <=> other` for a Float and a fixnum, a Float or a bignum.
# Returns -1, 0, 1, or 2 when they cannot be compared. A bignum
# compares exactly, through the Integer code, never through a rounded
# double.
sig [Value, Value] => Word
machine def zr_float_cmp_value(recv, other)
  if zr_fixnum_p(other)
    c = zr_int_float_cmp(zr_fix2long(other), zr_float_value(recv))
    return c == 2 ? 2 : 0 - c
  end
  if zr_big_p(other)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    r = zr_send(other, Machine.id(:<=>), 1, slot)
    if r == QUNDEF || r == QNIL
      return 2
    end
    return 0 - zr_fix2long(r)
  end
  zr_float_cmp(zr_float_value(recv), zr_float_value(other))
end

# `<`, `<=`, `>`, `>=` with a Float or Integer. The comparison fails
# for all other values.
sig [Value, Value, Word] => Value
machine def zr_flo_relate(recv, other, want)
  if !zr_fixnum_p(other) && !zr_float_p(other) && !zr_big_p(other)
    if want == 0
      return zr_num_coerce(recv, other, Machine.id(:<), 1)
    end
    if want == 1
      return zr_num_coerce(recv, other, Machine.id(:<=), 1)
    end
    if want == 2
      return zr_num_coerce(recv, other, Machine.id(:>), 1)
    end
    return zr_num_coerce(recv, other, Machine.id(:>=), 1)
  end
  c = zr_float_cmp_value(recv, other)
  if c == 2
    return Machine.value(QFALSE)
  end
  if want == 0
    return zr_bool(c < 0)
  end
  if want == 1
    return zr_bool(c <= 0)
  end
  if want == 2
    return zr_bool(c > 0)
  end
  zr_bool(c >= 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_lt(recv, argc, argv, cref, blk)
  zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_le(recv, argc, argv, cref, blk)
  zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_gt(recv, argc, argv, cref, blk)
  zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 2)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_ge(recv, argc, argv, cref, blk)
  zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 3)
end

# --- conversions ------------------------------------------------------

# Converts a double to an Integer, truncated. NaN and the infinities
# raise FloatDomainError. A value past the fixnum range becomes a bignum.
sig [F64] => Value
machine def zr_float_to_int(d)
  if zr_nan_p(d) || zr_inf_p(d)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_float(b, d)
    return zr_raise_buf(zr_core_class(Machine.id(:FloatDomainError)), b)
  end
  t = Machine.trunc(d)
  if Machine.fabs(t) >= Machine.f64(4886405595696988160)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_float_new(t)))
    return zr_send(zr_global(G_INTEGER), Machine.id(:big_from_float), 1, slot)
  end
  zr_fix(Machine.to_int(t))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_to_i(recv, argc, argv, cref, blk)
  zr_float_to_int(zr_float_value(recv))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_floor(recv, argc, argv, cref, blk)
  if argc > 0 && zr_fix2long(Machine.value(Machine.load64(argv, 0))) > 0
    return zr_float_round_digits(zr_float_value(recv), zr_fix2long(Machine.value(Machine.load64(argv, 0))), 1)
  end
  zr_float_to_int(Machine.floor(zr_float_value(recv)))
end

# `floor`, `ceil` and `round` to `digits` places, for the Float
# methods. Returns nil when the double cannot give an exact result.
sig [Value, Value] => Value
machine def zr_flo_floor_m(recv, digits)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(digits))
  zr_flo_floor(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Value] => Value
machine def zr_flo_ceil_m(recv, digits)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(digits))
  zr_flo_ceil(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Value] => Value
machine def zr_flo_round_m(recv, digits)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(digits))
  zr_flo_round(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_ceil(recv, argc, argv, cref, blk)
  if argc > 0 && zr_fix2long(Machine.value(Machine.load64(argv, 0))) > 0
    return zr_float_round_digits(zr_float_value(recv), zr_fix2long(Machine.value(Machine.load64(argv, 0))), 2)
  end
  zr_float_to_int(Machine.ceil(zr_float_value(recv)))
end

# CRuby's round_half_up: round(x * s) / s, with a correction when the
# scaled value is just below a half.
sig [F64, F64] => F64
machine def zr_round_half_up(x, s)
  xs = x * s
  f = Machine.nearest(xs)
  if Machine.fabs(xs - Machine.trunc(xs)) == Machine.f64(4602678819172646912)
    f = Machine.trunc(xs) + (xs > Machine.f64(0) ? Machine.f64(4607182418800017408) : -Machine.f64(4607182418800017408))
  end
  if s == Machine.f64(4607182418800017408)
    return f
  end
  if x > Machine.f64(0)
    if (f + Machine.f64(4602678819172646912)) / s <= x
      f = f + Machine.f64(4607182418800017408)
    end
    return f
  end
  if (f - Machine.f64(4602678819172646912)) / s >= x
    f = f - Machine.f64(4607182418800017408)
  end
  f
end

# `round(n)`, `floor(n)` and `ceil(n)` for n > 0 (`how` is 0, 1 or 2),
# as CRuby's rb_float_round, rb_float_floor and rb_float_ceil do them.
# A number with fewer digits than `n` returns itself. A number too
# small for the digits gives zero. floor corrects a scaled result that
# went past the number.
sig [F64, Word, Word] => Value
machine def zr_float_round_digits(d, digits, how)
  if d == Machine.f64(0) || zr_nan_p(d) || zr_inf_p(d) || zr_float_round_overflow(d, digits)
    return zr_float_new(d)
  end
  if zr_float_round_underflow(d, digits) && (how == 0 || (how == 1 && d > Machine.f64(0)) || (how == 2 && d < Machine.f64(0)))
    return zr_float_new(Machine.f64(0))
  end
  # CRuby's ACCURATE_POW10: after DBL_DIG places, the power of ten is
  # not exact. nil tells the caller to use the exact calculation.
  if digits > 14
    return Machine.value(QNIL)
  end
  s = pow(Machine.f64(4621819117588971520), Machine.to_f64(digits))
  if how == 0
    return zr_float_new(zr_round_half_up(d, s) / s)
  end
  if how == 1
    mul = Machine.floor(d * s)
    res = (mul + Machine.f64(4607182418800017408)) / s
    if res > d
      res = mul / s
    end
    return zr_float_new(res)
  end
  zr_float_new(Machine.ceil(d * s) / s)
end

# The binary exponent that frexp returns: the number is f * 2**e with
# f in [0.5, 1).
sig [F64] => Word
machine def zr_float_binexp(d)
  bits = Machine.ptr(Machine.bits(d))
  Machine.word((bits >> 52) & 2047) - 1022
end

# CRuby's float_round_overflow: for `digits` places, a number whose
# exponent leaves nothing to round returns itself.
sig [F64, Word] => Bool
machine def zr_float_round_overflow(d, digits)
  e = zr_float_binexp(d)
  digits >= 17 - (e > 0 ? e / 4 : (e / 3) - 1)
end

# CRuby's float_round_underflow: all the digits requested are above
# the number.
sig [F64, Word] => Bool
machine def zr_float_round_underflow(d, digits)
  e = zr_float_binexp(d)
  digits < 0 - (e > 0 ? (e / 3) + 1 : e / 4)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_round(recv, argc, argv, cref, blk)
  d = zr_float_value(recv)
  digits = 0
  if argc > 0
    if !zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
      zr_bug(Machine.bytes("Float#round with a half: mode is not implemented yet\n"), 53)
    end
    digits = zr_fix2long(Machine.value(Machine.load64(argv, 0)))
  end
  if digits > 0
    return zr_float_round_digits(d, digits, 0)
  end
  if digits < 0
    n = zr_float_to_int(Machine.trunc(d))
    return n if n == QUNDEF
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_fix(digits)))
    return zr_send(n, Machine.id(:round), 1, slot)
  end
  zr_float_to_int(zr_round_half_up(d, Machine.f64(4607182418800017408)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_nan_p(recv, argc, argv, cref, blk)
  zr_bool(zr_nan_p(zr_float_value(recv)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_infinite_p(recv, argc, argv, cref, blk)
  d = zr_float_value(recv)
  if zr_inf_p(d)
    return zr_fix(d < Machine.f64(0) ? 0 - 1 : 1)
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_finite_p(recv, argc, argv, cref, blk)
  d = zr_float_value(recv)
  zr_bool(!zr_nan_p(d) && !zr_inf_p(d))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_abs(recv, argc, argv, cref, blk)
  zr_float_new(Machine.fabs(zr_float_value(recv)))
end

# `hash`: the bits, with -0.0 as 0.0, so equal Floats have the same hash.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_hash(recv, argc, argv, cref, blk)
  d = zr_float_value(recv)
  if d == Machine.f64(0)
    d = Machine.f64(0)
  end
  bits = Machine.ptr(Machine.bits(d))
  zr_fix(Machine.word((bits ^ (bits >> 29)) & 4611686018427387903))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_eql_p(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if !zr_float_p(other)
    return Machine.value(QFALSE)
  end
  zr_bool(zr_float_value(recv) == zr_float_value(other))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_to_f(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:to_f), argc, argv)
  end
  zr_float_new(Machine.to_f64(zr_fix2long(recv)))
end

# A Float literal, from the bits that the compiler read.
sig [Word] => Value
machine def zr_float_from_bits(bits)
  zr_float_new(Machine.f64(bits))
end

# --- Ryu: the shortest digits that read back as the same double ----------
#
# Derived from Ryu (Copyright 2018 Ulf Adams, Apache License 2.0 or Boost
# Software License 1.0). See THIRD_PARTY_NOTICES.md.

# The high 64 bits of a * b, both unsigned, by 32-bit halves.
sig [Ptr, Ptr] => Ptr
machine def zr_umulh(a, b)
  a_lo = a & 4294967295
  a_hi = a >> 32
  b_lo = b & 4294967295
  b_hi = b >> 32
  lo_lo = a_lo * b_lo
  hi_lo = a_hi * b_lo
  lo_hi = a_lo * b_hi
  hi_hi = a_hi * b_hi
  cross = (lo_lo >> 32) + (hi_lo & 4294967295) + lo_hi
  hi_hi + (hi_lo >> 32) + (cross >> 32)
end

# (m * mul) >> j for a 128-bit `mul` at `row`, `j` past 64 and under 128.
sig [Ptr, Ptr, Word] => Ptr
machine def zr_ryu_mul_shift(m, row, j)
  mul0 = Machine.ptr(Machine.load64(row, 0))
  mul1 = Machine.ptr(Machine.load64(row, 8))
  b0_hi = zr_umulh(m, mul0)
  b2_lo = m * mul1
  b2_hi = zr_umulh(m, mul1)
  sum = b0_hi + b2_lo
  if sum < b0_hi
    b2_hi = b2_hi + 1
  end
  dist = j - 64
  (sum >> dist) | (b2_hi << (64 - dist))
end

sig [Word] => Word
machine def zr_pow5_bits(e)
  ((e * 1217359) >> 19) + 1
end

# Whether `v` divides by five at least `p` times.
sig [Ptr, Word] => Bool
machine def zr_multiple_of_pow5(v, p)
  n = 0
  while v > 0 && v % 5 == 0
    v = v / 5
    n += 1
  end
  n >= p
end

sig [Ptr, Word] => Bool
machine def zr_multiple_of_pow2(v, p)
  (v & ((Machine.ptr(1) << p) - 1)) == 0
end

# The decimal digits of a finite, nonzero, positive double: the
# significand `out[0]` and the power of ten `out[1]`.
sig [F64, Ptr] => Void
machine def zr_ryu(d, out)
  bits = Machine.ptr(Machine.bits(d))
  ieee_mantissa = bits & 4503599627370495
  ieee_exponent = Machine.word((bits >> 52) & 2047)
  if ieee_exponent == 0
    e2 = 0 - 1076
    m2 = ieee_mantissa
  else
    e2 = ieee_exponent - 1077
    m2 = Machine.ptr(4503599627370496) | ieee_mantissa
  end
  even = (m2 & 1) == 0
  accept_bounds = even
  mv = m2 * 4
  mm_shift = ieee_mantissa != 0 || ieee_exponent <= 1 ? 1 : 0
  vm_trailing = false
  vr_trailing = false
  if e2 >= 0
    q = ((e2 * 78913) >> 18) - (e2 > 3 ? 1 : 0)
    e10 = q
    k = 125 + zr_pow5_bits(q) - 1
    i = (0 - e2) + q + k
    row = zr_ryu_pow5_inv() + (q * 16)
    vr = zr_ryu_mul_shift(mv, row, i)
    vp = zr_ryu_mul_shift(mv + 2, row, i)
    vm = zr_ryu_mul_shift(mv - 1 - mm_shift, row, i)
    if q <= 21
      if mv % 5 == 0
        vr_trailing = zr_multiple_of_pow5(mv, q)
      elsif accept_bounds
        vm_trailing = zr_multiple_of_pow5(mv - 1 - mm_shift, q)
      elsif zr_multiple_of_pow5(mv + 2, q)
        vp = vp - 1
      end
    end
  else
    q = (((0 - e2) * 732923) >> 20) - ((0 - e2) > 1 ? 1 : 0)
    e10 = q + e2
    i = (0 - e2) - q
    k = zr_pow5_bits(i) - 125
    j = q - k
    row = zr_ryu_pow5() + (i * 16)
    vr = zr_ryu_mul_shift(mv, row, j)
    vp = zr_ryu_mul_shift(mv + 2, row, j)
    vm = zr_ryu_mul_shift(mv - 1 - mm_shift, row, j)
    if q <= 1
      vr_trailing = true
      if accept_bounds
        vm_trailing = mm_shift == 1
      else
        vp = vp - 1
      end
    elsif q < 63
      vr_trailing = zr_multiple_of_pow2(mv, q)
    end
  end
  removed = 0
  last_removed = 0
  if vm_trailing || vr_trailing
    while vp / 10 > vm / 10
      vm_trailing = vm_trailing && vm % 10 == 0
      vr_trailing = vr_trailing && last_removed == 0
      last_removed = Machine.word(vr % 10)
      vr = vr / 10
      vp = vp / 10
      vm = vm / 10
      removed += 1
    end
    if vm_trailing
      while vm % 10 == 0
        vr_trailing = vr_trailing && last_removed == 0
        last_removed = Machine.word(vr % 10)
        vr = vr / 10
        vp = vp / 10
        vm = vm / 10
        removed += 1
      end
    end
    if vr_trailing && last_removed == 5 && vr % 2 == 0
      last_removed = 4
    end
    output = vr
    if (vr == vm && (!accept_bounds || !vm_trailing)) || last_removed >= 5
      output = output + 1
    end
  else
    round_up = false
    while vp / 10 > vm / 10
      round_up = vr % 10 >= 5
      vr = vr / 10
      vp = vp / 10
      vm = vm / 10
      removed += 1
    end
    output = vr
    if vr == vm || round_up
      output = output + 1
    end
  end
  Machine.store64(out, 0, Machine.word(output))
  Machine.store64(out, 8, e10 + removed)
end

# --- to_s ----------------------------------------------------------------

# Writes a double into `b` as Float#to_s does. It writes digits with a
# decimal point when the decimal exponent is between -3 and 15 (or 16
# with a fraction), else `d.ddde+XX`. NaN, Infinity and -Infinity are
# written by name.
sig [Ptr, F64] => Void
machine def zr_buf_float(b, d)
  if zr_nan_p(d)
    zr_buf_push(b, Machine.bytes("NaN"), 3)
    return
  end
  if zr_inf_p(d)
    if d < Machine.f64(0)
      zr_buf_push(b, Machine.bytes("-Infinity"), 9)
    else
      zr_buf_push(b, Machine.bytes("Infinity"), 8)
    end
    return
  end
  if (Machine.ptr(Machine.bits(d)) >> 63) != 0
    zr_buf_byte(b, 45)
    d = -d
  end
  if d == Machine.f64(0)
    zr_buf_push(b, Machine.bytes("0.0"), 3)
    return
  end
  out = Machine.slot(16)
  zr_ryu(d, out)
  digits = Machine.slot(24)
  n = zr_digits_of(Machine.load64(out, 0), digits)
  decpt = Machine.load64(out, 8) + n
  if decpt > 0 && (decpt <= 15 || (decpt == 16 && n > decpt))
    if decpt >= n
      zr_buf_push(b, digits, n)
      i = n
      while i < decpt
        zr_buf_byte(b, 48)
        i += 1
      end
      zr_buf_push(b, Machine.bytes(".0"), 2)
    else
      zr_buf_push(b, digits, decpt)
      zr_buf_byte(b, 46)
      zr_buf_push(b, digits + decpt, n - decpt)
    end
  elsif decpt <= 0 && decpt > 0 - 4
    zr_buf_push(b, Machine.bytes("0."), 2)
    i = decpt
    while i < 0
      zr_buf_byte(b, 48)
      i += 1
    end
    zr_buf_push(b, digits, n)
  else
    zr_buf_byte(b, Machine.word(Machine.load8(digits, 0)))
    zr_buf_byte(b, 46)
    if n > 1
      zr_buf_push(b, digits + 1, n - 1)
    else
      zr_buf_byte(b, 48)
    end
    zr_buf_byte(b, 101)
    e = decpt - 1
    if e < 0
      zr_buf_byte(b, 45)
      e = 0 - e
    else
      zr_buf_byte(b, 43)
    end
    if e < 10
      zr_buf_byte(b, 48)
    end
    zr_buf_long(b, e)
  end
end

# Writes the decimal digits of `n` into `buf` and returns their count.
sig [Word, Ptr] => Word
machine def zr_digits_of(n, buf)
  tmp = Machine.slot(24)
  i = 0
  if n == 0
    Machine.store8(buf, 0, Machine.i8(48))
    return 1
  end
  while n > 0
    Machine.store8(tmp + i, 0, Machine.i8(48 + (n % 10)))
    n = n / 10
    i += 1
  end
  j = 0
  while j < i
    Machine.store8(buf + j, 0, Machine.load8(tmp + (i - 1 - j), 0))
    j += 1
  end
  i
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_to_s(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_float(b, zr_float_value(recv))
  zr_buf_take_at(b, ENC_USASCII)
end

# --- parsing and libm -----------------------------------------------------
Machine.import "strtod", [Ptr, Ptr] => F64
Machine.import "cbrt", [F64] => F64
Machine.import "sin", [F64] => F64
Machine.import "cos", [F64] => F64
Machine.import "tan", [F64] => F64
Machine.import "atan", [F64] => F64
Machine.import "exp", [F64] => F64
Machine.import "atan2", [F64, F64] => F64
Machine.import "hypot", [F64, F64] => F64
Machine.import "sinh", [F64] => F64
Machine.import "cosh", [F64] => F64
Machine.import "tanh", [F64] => F64
Machine.import "log", [F64] => F64
Machine.import "log2", [F64] => F64
Machine.import "log10", [F64] => F64
Machine.import "asin", [F64] => F64
Machine.import "acos", [F64] => F64
Machine.import "asinh", [F64] => F64
Machine.import "acosh", [F64] => F64
Machine.import "atanh", [F64] => F64
Machine.import "tgamma", [F64] => F64
Machine.import "lgamma_r", [F64, Ptr] => F64
Machine.import "erf", [F64] => F64
Machine.import "erfc", [F64] => F64
Machine.import "expm1", [F64] => F64
Machine.import "log1p", [F64] => F64
Machine.import "ldexp", [F64, I32] => F64
Machine.import "frexp", [F64, Ptr] => F64

# cos(pi * x) and sin(pi * x), as complex.c computes them when libm has
# no __cospi and __sinpi: it multiplies x by pi first.
PI_BITS = 4614256656552045848

sig [F64] => F64
machine def zr_cos_of_pi_times(x)
  cos(x * Machine.f64(PI_BITS))
end

sig [F64] => F64
machine def zr_sin_of_pi_times(x)
  sin(x * Machine.f64(PI_BITS))
end

sig [Ptr, Word] => Bool
machine def zr_digit_at(p, i)
  c = Machine.word(Machine.load8(p + i, 0))
  c >= 48 && c <= 57
end

# Reads Ruby's decimal Float syntax from `s`: sign, digits with single
# underscores between them, a fraction (or a bare point after digits),
# and an exponent. The digits go to `b` without underscores, for
# strtod. Returns the number of bytes read, or -1 when the text does
# not start with a number.
sig [Value, Ptr] => Word
machine def zr_float_scan(s, b)
  p = RString.ptr(s)
  n = RString.len(s)
  i = 0
  while i < n && (Machine.word(Machine.load8(p + i, 0)) == 32 || (Machine.word(Machine.load8(p + i, 0)) >= 9 && Machine.word(Machine.load8(p + i, 0)) <= 13))
    i += 1
  end
  if i < n && (Machine.word(Machine.load8(p + i, 0)) == 45 || Machine.word(Machine.load8(p + i, 0)) == 43)
    zr_buf_byte(b, Machine.word(Machine.load8(p + i, 0)))
    i += 1
  end
  digits = 0
  while i < n && zr_digit_at(p, i)
    zr_buf_byte(b, Machine.word(Machine.load8(p + i, 0)))
    digits += 1
    i += 1
    if i + 1 < n && Machine.word(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
      i += 1
    end
  end
  fraction = 0
  if digits > 0 && i < n && Machine.word(Machine.load8(p + i, 0)) == 46 && !(i + 1 < n && zr_digit_at(p, i + 1))
    i += 1
  elsif i + 1 < n && Machine.word(Machine.load8(p + i, 0)) == 46 && zr_digit_at(p, i + 1)
    zr_buf_byte(b, 46)
    i += 1
    while i < n && zr_digit_at(p, i)
      zr_buf_byte(b, Machine.word(Machine.load8(p + i, 0)))
      fraction += 1
      i += 1
      if i + 1 < n && Machine.word(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
        i += 1
      end
    end
  end
  if digits == 0 && fraction == 0
    return 0 - 1
  end
  if i < n && (Machine.word(Machine.load8(p + i, 0)) == 101 || Machine.word(Machine.load8(p + i, 0)) == 69)
    j = i + 1
    if j < n && (Machine.word(Machine.load8(p + j, 0)) == 45 || Machine.word(Machine.load8(p + j, 0)) == 43)
      j += 1
    end
    if j < n && zr_digit_at(p, j)
      zr_buf_byte(b, 101)
      k = i + 1
      while k < j
        zr_buf_byte(b, Machine.word(Machine.load8(p + k, 0)))
        k += 1
      end
      i = j
      while i < n && zr_digit_at(p, i)
        zr_buf_byte(b, Machine.word(Machine.load8(p + i, 0)))
        i += 1
        if i + 1 < n && Machine.word(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
          i += 1
        end
      end
    end
  end
  i
end

sig [Ptr] => F64
machine def zr_buf_strtod(b)
  zr_buf_byte(b, 0)
  d = strtod(Buf.ptr(b), 0)
  zr_buf_free(b)
  d
end

# `String#to_f`: the number at the start of the text, or 0.0.
sig [Value] => Value
machine def zr_str_to_f(s)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  n = zr_float_scan(s, b)
  if n < 0
    zr_buf_free(b)
    return zr_float_new(Machine.f64(0))
  end
  zr_float_new(zr_buf_strtod(b))
end

# `Float(text)`: all the text, except whitespace, must be a number.
# Returns nil when it is not. A hex form goes to `zr_hex_to_f`.
sig [Value] => Value
machine def zr_str_to_f_strict(s)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  n = zr_float_scan(s, b)
  if n < 0
    zr_buf_free(b)
    return Machine.value(QNIL)
  end
  p = RString.ptr(s)
  len = RString.len(s)
  if n + 1 < len && (Machine.word(Machine.load8(p + n, 0)) == 120 || Machine.word(Machine.load8(p + n, 0)) == 88) && zr_buf_last_is_zero(b)
    zr_buf_free(b)
    return zr_hex_to_f(s)
  end
  while n < len && (Machine.word(Machine.load8(p + n, 0)) == 32 || (Machine.word(Machine.load8(p + n, 0)) >= 9 && Machine.word(Machine.load8(p + n, 0)) <= 13))
    n += 1
  end
  if n != len
    zr_buf_free(b)
    return Machine.value(QNIL)
  end
  zr_float_new(zr_buf_strtod(b))
end

# `Float("0x1p+3")`: strtod reads the hex form itself, so all the text
# goes to it. The end pointer shows whether it read all the text.
sig [Value] => Value
machine def zr_hex_to_f(s)
  p = RString.ptr(s)
  len = RString.len(s)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = 0
  while i < len
    c = Machine.word(Machine.load8(p + i, 0))
    if c != 95
      zr_buf_byte(b, c)
    end
    i += 1
  end
  zr_buf_byte(b, 0)
  last = Machine.slot(8)
  Machine.store64(last, 0, 0)
  d = strtod(Buf.ptr(b), last)
  stop = Machine.ptr(Machine.load64(last, 0))
  read = stop == 0 ? 0 : stop - Buf.ptr(b)
  while read > 0 && read < Buf.len(b) - 1 && (Machine.word(Machine.load8(Buf.ptr(b) + read, 0)) == 32 || (Machine.word(Machine.load8(Buf.ptr(b) + read, 0)) >= 9 && Machine.word(Machine.load8(Buf.ptr(b) + read, 0)) <= 13))
    read += 1
  end
  ok = read > 0 && read == Buf.len(b) - 1
  zr_buf_free(b)
  ok ? zr_float_new(d) : Machine.value(QNIL)
end

sig [Ptr] => Bool
machine def zr_buf_last_is_zero(b)
  Buf.len(b) > 0 && Machine.word(Machine.load8(Buf.ptr(b) + Buf.len(b) - 1, 0)) == 48
end

sig [Value, Value] => Value
machine def zr_float_quotient_value(a, b)
  zr_float_new(zr_float_quotient(zr_float_value(a), zr_float_value(b)))
end

sig [Value] => Value
machine def zr_math_sqrt(x)
  zr_float_new(Machine.sqrt(zr_float_value(x)))
end

# `Math.sqrt(x)` for a Float or fixnum `x` in the domain, else nil. It
# does the send of `check`, the two comparisons and the call of the
# general path in one function. A zero gives +0.0, as CRuby's math_sqrt
# does for -0.0.
sig [Value] => Value
machine def zr_math_sqrt_fast(x)
  d = Machine.f64(0)
  if zr_fixnum_p(x)
    d = Machine.to_f64(zr_fix2long(x))
  elsif zr_float_p(x)
    d = zr_float_value(x)
  else
    return Machine.value(QNIL)
  end
  if d < Machine.f64(0)
    return Machine.value(QNIL)
  end
  if d == Machine.f64(0)
    return Machine.value(FLONUM_ZERO)
  end
  zr_float_new(Machine.sqrt(d))
end

# `zr_math_call(which, x)` for a Float or fixnum `x`, else nil. The
# functions with no domain check try this first.
sig [Value, Value] => Value
machine def zr_math_call_fast(which, x)
  if zr_fixnum_p(x)
    return zr_math_call(which, zr_float_new(Machine.to_f64(zr_fix2long(x))), Machine.value(QNIL))
  end
  if !zr_float_p(x)
    return Machine.value(QNIL)
  end
  zr_math_call(which, x, Machine.value(QNIL))
end

# Calls one libm function, selected by number, on one or two doubles.
sig [Value, Value, Value] => Value
machine def zr_math_call(which, x, y)
  w = zr_fix2long(which)
  a = zr_float_value(x)
  c = Machine.f64(0)
  if zr_float_p(y)
    c = zr_float_value(y)
  end
  if w == 1
    return zr_float_new(cbrt(a))
  elsif w == 2
    return zr_float_new(sin(a))
  elsif w == 3
    return zr_float_new(cos(a))
  elsif w == 4
    return zr_float_new(tan(a))
  elsif w == 5
    return zr_float_new(atan(a))
  elsif w == 6
    return zr_float_new(exp(a))
  elsif w == 7
    return zr_float_new(atan2(a, c))
  elsif w == 8
    return zr_float_new(hypot(a, c))
  elsif w == 9
    return zr_float_new(sinh(a))
  elsif w == 10
    return zr_float_new(cosh(a))
  elsif w == 11
    return zr_float_new(tanh(a))
  elsif w == 12
    return zr_float_new(log(a))
  elsif w == 13
    return zr_float_new(log2(a))
  elsif w == 14
    return zr_float_new(log10(a))
  elsif w == 15
    return zr_float_new(asin(a))
  elsif w == 16
    return zr_float_new(acos(a))
  elsif w == 17
    return zr_float_new(asinh(a))
  elsif w == 18
    return zr_float_new(acosh(a))
  elsif w == 19
    return zr_float_new(atanh(a))
  elsif w == 20
    return zr_float_new(tgamma(a))
  elsif w == 21
    return zr_float_new(erf(a))
  elsif w == 22
    return zr_float_new(erfc(a))
  elsif w == 23
    return zr_float_new(ldexp(a, Machine.i32(zr_fix2long(y))))
  elsif w == 24
    return zr_float_new(expm1(a))
  elsif w == 25
    return zr_float_new(log1p(a))
  end
  zr_float_new(lgamma_r(a, Machine.slot(4)))
end

# `[mantissa, exponent]` of frexp: the fraction in [0.5, 1) and the
# power of two.
sig [Value] => Value
machine def zr_math_frexp(x)
  e = Machine.slot(4)
  Machine.store32(e, 0, Machine.i32(0))
  m = frexp(zr_float_value(x), e)
  out = zr_ary_new(2)
  zr_ary_push(out, zr_float_new(m))
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(e, 0))))
  out
end

# `[log|gamma|, sign]` of lgamma.
sig [Value] => Value
machine def zr_math_lgamma(x)
  s = Machine.slot(4)
  Machine.store32(s, 0, Machine.i32(1))
  v = lgamma_r(zr_float_value(x), s)
  out = zr_ary_new(2)
  zr_ary_push(out, zr_float_new(v))
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(s, 0))))
  out
end

# The adjacent double. `up` moves toward +Infinity. From a zero, the
# result is the smallest subnormal. An infinity does not change, and
# NaN stays NaN.
sig [Value, Word] => Value
machine def zr_float_adjacent(recv, up)
  d = zr_float_value(recv)
  if zr_nan_p(d) || zr_inf_p(d)
    return recv
  end
  bits = Machine.bits(d)
  if d == Machine.f64(0)
    return zr_float_from_bits(up != 0 ? 1 : 0 - 9223372036854775807)
  end
  if (d > Machine.f64(0)) == (up != 0)
    return zr_float_from_bits(bits + 1)
  end
  zr_float_from_bits(bits - 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_next_float(recv, argc, argv, cref, blk)
  zr_float_adjacent(recv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_flo_prev_float(recv, argc, argv, cref, blk)
  zr_float_adjacent(recv, 0)
end

# The shortest digits that read back as the same double, and the
# position of the decimal point: `0.d1d2... * 10^point`.
sig [Value] => Value
machine def zr_float_shortest(v)
  d = zr_float_value(v)
  if d < Machine.f64(0)
    d = -d
  end
  out = zr_ary_new(2)
  if d == Machine.f64(0)
    zr_ary_push(out, zr_str_new(Machine.bytes("0"), 1))
    zr_ary_push(out, zr_fix(1))
    return out
  end
  pair = Machine.slot(16)
  zr_ryu(d, pair)
  digits = Machine.slot(24)
  n = zr_digits_of(Machine.load64(pair, 0), digits)
  zr_ary_push(out, zr_str_new(digits, n))
  zr_ary_push(out, zr_fix(Machine.load64(pair, 8) + n))
  out
end

# The IEEE 754 bit patterns of a double, as two 32-bit halves (low
# first), so the core can pack it without a bignum.
sig [Value] => Value
machine def zr_float_halves(v)
  bits = Machine.ptr(Machine.bits(zr_float_value(v)))
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(bits & 4294967295)))
  zr_ary_push(out, zr_fix(Machine.word(bits >> 32)))
  out
end

sig [Value, Value] => Value
machine def zr_float_of_halves(low, high)
  zr_float_from_bits((zr_fix2long(high) << 32) | zr_fix2long(low))
end

# CRuby's float_decode_internal: [mantissa, exponent], where the double
# is mantissa * 2**exponent. The mantissa is a 53-bit Integer (with the
# sign), so a Rational can contain the exact value.
sig [Value] => Value
machine def zr_float_decode(v)
  bits = Machine.ptr(Machine.bits(zr_float_value(v)))
  negative = (bits >> 63) != 0
  biased = (bits >> 52) & 2047
  fraction = bits & 4503599627370495
  mantissa = 0
  exponent = 0
  if biased == 0
    mantissa = fraction
    exponent = 0 - 1074
  else
    mantissa = fraction | 4503599627370496
    exponent = biased - 1075
  end
  while mantissa != 0 && (mantissa & 1) == 0
    mantissa = mantissa >> 1
    exponent += 1
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(negative ? 0 - Machine.word(mantissa) : Machine.word(mantissa)))
  zr_ary_push(out, zr_fix(exponent))
  out
end
