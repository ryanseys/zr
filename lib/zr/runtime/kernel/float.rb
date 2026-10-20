# Derived from Ryu (Apache-2.0 or Boost-1.0); see THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # Float: a double, stored as a flonum (CRuby's rotation, when the
  # exponent fits) or in a heap cell. This file has the shortest
  # round-trip digits (Ryu), CRuby's to_s layout, and the arithmetic and
  # comparisons, also with Integer operands.

  class RFloat < Layout
    attr_reader :basic #: RBasic
    attr_accessor :bits #: word
  end

  T_FLOAT = 4
  G_FLOAT = 40
  # The flonum +0.0, 0x8000000000000002, as a signed Word.
  FLONUM_ZERO = -9223372036854775806
  INF_BITS = 9218868437227405312
  # The gates of the Float operators that compiled code inlines for
  # flonums (`float_path` in the lowering). The Integer gates are in
  # lib/zr/runtime/kernel/integer.rb.
  GATE_FLO_PLUS = 4194304
  GATE_FLO_MINUS = 8388608
  GATE_FLO_MUL = 16777216
  GATE_FLO_DIV = 33554432
  GATE_FLO_LT = 67108864
  GATE_FLO_LE = 134217728
  GATE_FLO_GT = 268435456
  GATE_FLO_GE = 536870912
  GATE_FLO_EQ = 1073741824

  #: (value) -> bool
  def zr_flonum_p(v)
    (Machine.word(v) & 3) == 2
  end

  #: (value) -> bool
  def zr_float_p(v)
    zr_flonum_p(v) || (!zr_special_p(v) && zr_type(v) == T_FLOAT)
  end

  #: (value) -> value
  def zr_float_p_m(v)
    zr_bool(zr_float_p(v))
  end

  # Whether `v` is an Integer: a fixnum or a bignum.
  #: (value) -> value
  def zr_integer_p_m(v)
    zr_bool(zr_fixnum_p(v) || zr_big_p(v))
  end

  # Makes a Float from a double: a flonum when the top bits of the
  # exponent are 011 or 100, the flonum zero for +0.0, else a heap cell.
  #: (f64) -> value
  def zr_float_new(d)
    b = Machine.ptr(Machine.bits(d))
    top = (b >> 60) & 7
    if b != 3458764513820540928 && (top == 3 || top == 4)
      rotated = Machine.ushl_wrap(b, 3) | (b >> 61)
      return Machine.value((rotated & 18446744073709551614) | 2)
    end
    if b == 0
      return Machine.value(FLONUM_ZERO)
    end
    f = zr_alloc(T_FLOAT, zr_global(G_FLOAT), RFloat.size)
    RFloat[f].bits = Machine.word(b)
    RBasic[f].flags = RBasic[f].flags | FL_FREEZE
    f
  end

  #: (value) -> f64
  def zr_float_value(v)
    if zr_flonum_p(v)
      if Machine.word(v) == FLONUM_ZERO
        return Machine.f64(0)
      end
      w = Machine.ptr(v)
      b63 = w >> 63
      x = (2 - b63) | (w & 18446744073709551612)
      return Machine.f64((x >> 3) | Machine.ushl_wrap(x, 61))
    end
    Machine.f64(RFloat[v].bits)
  end

  # Converts a Float or Integer operand to a double. For all other values
  # it raises a TypeError and returns undef (it does not call `coerce`).
  #: (value, value, ptr, word, word) -> value
  def zr_float_operand(recv, v, out, mid, kind)
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

  #: (f64) -> bool
  def zr_nan_p(d)
    d != d
  end

  #: (f64) -> bool
  def zr_inf_p(d)
    Machine.fabs(d) == Machine.f64(INF_BITS)
  end

  # --- arithmetic -------------------------------------------------------

  #: (value, word, ptr, value, value) -> value
  def zr_flo_plus(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:+), 0)
    return r if r != QNIL
    zr_float_new(zr_float_value(recv) + Machine.f64(Machine.load64(out, 0)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_minus(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:-), 0)
    return r if r != QNIL
    zr_float_new(zr_float_value(recv) - Machine.f64(Machine.load64(out, 0)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_mul(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:*), 0)
    return r if r != QNIL
    zr_float_new(zr_float_value(recv) * Machine.f64(Machine.load64(out, 0)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_div(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:/), 0)
    return r if r != QNIL
    zr_float_new(zr_float_value(recv) / Machine.f64(Machine.load64(out, 0)))
  end

  # CRuby's flodivmod: the modulo takes the divisor's sign.
  #: (f64, f64) -> f64
  def zr_float_mod(x, y)
    if zr_nan_p(y)
      return y
    end
    if x == Machine.f64(0) || (zr_inf_p(y) && !zr_inf_p(x))
      m = x
    else
      m = Libc.fmod(x, y)
    end
    if y * m < Machine.f64(0)
      m = m + y
    end
    m
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_mod(recv, argc, argv, cref, blk)
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
  #: (f64, f64) -> f64
  def zr_float_quotient(x, y)
    if zr_nan_p(y)
      return y
    end
    if x == Machine.f64(0) || (zr_inf_p(y) && !zr_inf_p(x))
      m = x
    else
      m = Libc.fmod(x, y)
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
  #: (f64, f64) -> value
  def zr_complex_polar_pi(abs, ang)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_pow(recv, argc, argv, cref, blk)
    out = Machine.slot(8)
    r = zr_float_operand(recv, Machine.value(Machine.load64(argv, 0)), out, Machine.id(:**), 0)
    return r if r != QNIL
    x = zr_float_value(recv)
    y = Machine.f64(Machine.load64(out, 0))
    if x < Machine.f64(0) && y != Machine.nearest(y)
      return zr_complex_polar_pi(Libc.pow(Machine.f64(0) - x, y), y)
    end
    zr_float_new(Libc.pow(x, y))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_uminus(recv, argc, argv, cref, blk)
    zr_float_new(-zr_float_value(recv))
  end

  # --- comparison -------------------------------------------------------

  # Returns -1, 0, 1, or 2 when one side is NaN.
  #: (f64, f64) -> word
  def zr_float_cmp(a, b)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_fixnum_p(other) || zr_float_p(other) || zr_big_p(other)
      return zr_bool(zr_float_cmp_value(recv, other) == 0)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    zr_send(other, Machine.id(:==), 1, slot)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_cmp(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if !zr_fixnum_p(other) && !zr_float_p(other) && !zr_big_p(other)
      # flo_cmp: an infinite receiver asks the other value's infinite?.
      a = zr_float_value(recv)
      positive = a > Machine.to_f64(0)
      if zr_inf_p(a) && zr_check_funcall(other, Machine.id(:infinite?)) == QTRUE
        i = zr_send(other, Machine.id(:infinite?), 0, 0)
        return i if i == QUNDEF
        if i == QNIL || i == QFALSE
          return zr_fix(positive ? 1 : 0 - 1)
        end
        j = zr_fixnum_p(i) ? zr_fix2long(i) : 1
        if positive
          return zr_fix(j > 0 ? 0 : 1)
        end
        return zr_fix(j < 0 ? 0 : 0 - 1)
      end
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
  #: (value, value) -> word
  def zr_float_cmp_value(recv, other)
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
  #: (value, value, word) -> value
  def zr_flo_relate(recv, other, want)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_lt(recv, argc, argv, cref, blk)
    zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_le(recv, argc, argv, cref, blk)
    zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 1)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_gt(recv, argc, argv, cref, blk)
    zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 2)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_ge(recv, argc, argv, cref, blk)
    zr_flo_relate(recv, Machine.value(Machine.load64(argv, 0)), 3)
  end

  # --- conversions ------------------------------------------------------

  # Converts a double to an Integer, truncated. NaN and the infinities
  # raise FloatDomainError. A value past the fixnum range becomes a bignum.
  #: (f64) -> value
  def zr_float_to_int(d)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_to_i(recv, argc, argv, cref, blk)
    zr_float_to_int(zr_float_value(recv))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_floor(recv, argc, argv, cref, blk)
    if argc > 0 && zr_fix2long(Machine.value(Machine.load64(argv, 0))) > 0
      return zr_float_round_digits(zr_float_value(recv), zr_fix2long(Machine.value(Machine.load64(argv, 0))), 1)
    end
    zr_float_to_int(Machine.floor(zr_float_value(recv)))
  end

  # `floor`, `ceil` and `round` to `digits` places, for the Float
  # methods. Returns nil when the double cannot give an exact result.
  #: (value, value) -> value
  def zr_flo_floor_m(recv, digits)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(digits))
    zr_flo_floor(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, value) -> value
  def zr_flo_ceil_m(recv, digits)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(digits))
    zr_flo_ceil(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, value) -> value
  def zr_flo_round_m(recv, digits)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(digits))
    zr_flo_round(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_ceil(recv, argc, argv, cref, blk)
    if argc > 0 && zr_fix2long(Machine.value(Machine.load64(argv, 0))) > 0
      return zr_float_round_digits(zr_float_value(recv), zr_fix2long(Machine.value(Machine.load64(argv, 0))), 2)
    end
    zr_float_to_int(Machine.ceil(zr_float_value(recv)))
  end

  # CRuby's round_half_up: round(x * s) / s, with a correction when the
  # scaled value is just below a half.
  #: (f64, f64) -> f64
  def zr_round_half_up(x, s)
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
  #: (f64, word, word) -> value
  def zr_float_round_digits(d, digits, how)
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
    s = Libc.pow(Machine.f64(4621819117588971520), Machine.to_f64(digits))
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
  #: (f64) -> word
  def zr_float_binexp(d)
    bits = Machine.ptr(Machine.bits(d))
    Machine.word((bits >> 52) & 2047) - 1022
  end

  # CRuby's float_round_overflow: for `digits` places, a number whose
  # exponent leaves nothing to round returns itself.
  #: (f64, word) -> bool
  def zr_float_round_overflow(d, digits)
    e = zr_float_binexp(d)
    digits >= 17 - (e > 0 ? e / 4 : Machine.sdiv(e, 3) - 1)
  end

  # CRuby's float_round_underflow: all the digits requested are above
  # the number.
  #: (f64, word) -> bool
  def zr_float_round_underflow(d, digits)
    e = zr_float_binexp(d)
    digits < 0 - (e > 0 ? (e / 3) + 1 : Machine.sdiv(e, 4))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_round(recv, argc, argv, cref, blk)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_nan_p(recv, argc, argv, cref, blk)
    zr_bool(zr_nan_p(zr_float_value(recv)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_infinite_p(recv, argc, argv, cref, blk)
    d = zr_float_value(recv)
    if zr_inf_p(d)
      return zr_fix(d < Machine.f64(0) ? 0 - 1 : 1)
    end
    Machine.value(QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_finite_p(recv, argc, argv, cref, blk)
    d = zr_float_value(recv)
    zr_bool(!zr_nan_p(d) && !zr_inf_p(d))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_abs(recv, argc, argv, cref, blk)
    zr_float_new(Machine.fabs(zr_float_value(recv)))
  end

  # `hash`: the bits, with -0.0 as 0.0, so equal Floats have the same hash.
  #: (value, word, ptr, value, value) -> value
  def zr_flo_hash(recv, argc, argv, cref, blk)
    # With -0.0 as 0.0 and the run's seed, as the table hashes it.
    zr_fix(zr_value_hash(recv))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_eql_p(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if !zr_float_p(other)
      return Machine.value(QFALSE)
    end
    zr_bool(zr_float_value(recv) == zr_float_value(other))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_int_to_f(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:to_f), argc, argv)
    end
    zr_float_new(Machine.to_f64(zr_fix2long(recv)))
  end

  # A Float literal, from the bits that the compiler read.
  #: (word) -> value
  def zr_float_from_bits(bits)
    zr_float_new(Machine.f64(bits))
  end

  # --- Ryu: the shortest digits that read back as the same double ----------
  #
  # Derived from Ryu (Copyright 2018 Ulf Adams, Apache License 2.0 or Boost
  # Software License 1.0). See THIRD_PARTY_NOTICES.md.

  # The high 64 bits of a * b, both unsigned, by 32-bit halves.
  #: (ptr, ptr) -> ptr
  def zr_umulh(a, b)
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
  #: (ptr, ptr, word) -> ptr
  def zr_ryu_mul_shift(m, row, j)
    mul0 = Machine.ptr(Machine.load64(row, 0))
    mul1 = Machine.ptr(Machine.load64(row, 8))
    b0_hi = zr_umulh(m, mul0)
    # The low 64 bits of the product, the sum with its carry, and the
    # bits of a 128-bit value: each wraps at 2**64 on purpose.
    b2_lo = Machine.umul_wrap(m, mul1)
    b2_hi = zr_umulh(m, mul1)
    sum = Machine.uadd_wrap(b0_hi, b2_lo)
    if sum < b0_hi
      b2_hi = b2_hi + 1
    end
    dist = j - 64
    (sum >> dist) | Machine.ushl_wrap(b2_hi, 64 - dist)
  end

  #: (word) -> word
  def zr_pow5_bits(e)
    ((e * 1217359) >> 19) + 1
  end

  # Whether `v` divides by five at least `p` times.
  #: (ptr, word) -> bool
  def zr_multiple_of_pow5(v, p)
    n = 0
    while v > 0 && v % 5 == 0
      v = v / 5
      n += 1
    end
    n >= p
  end

  #: (ptr, word) -> bool
  def zr_multiple_of_pow2(v, p)
    (v & ((Machine.ptr(1) << p) - 1)) == 0
  end

  # The decimal digits of a finite, nonzero, positive double: the
  # significand `out[0]` and the power of ten `out[1]`.
  #: (f64, ptr) -> void
  def zr_ryu(d, out)
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
  #: (ptr, f64) -> void
  def zr_buf_float(b, d)
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
      zr_buf_byte(b, Machine.u8(Machine.load8(digits, 0)))
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
  #: (word, ptr) -> word
  def zr_digits_of(n, buf)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_to_s(recv, argc, argv, cref, blk)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_float(b, zr_float_value(recv))
    zr_buf_take_at(b, ENC_USASCII)
  end

  # --- parsing and libm -----------------------------------------------------

  # cos(pi * x) and sin(pi * x), as complex.c computes them when libm has
  # no __cospi and __sinpi: it multiplies x by pi first.
  PI_BITS = 4614256656552045848

  #: (f64) -> f64
  def zr_cos_of_pi_times(x)
    Libc.cos(x * Machine.f64(PI_BITS))
  end

  #: (f64) -> f64
  def zr_sin_of_pi_times(x)
    Libc.sin(x * Machine.f64(PI_BITS))
  end

  #: (ptr, word) -> bool
  def zr_digit_at(p, i)
    c = Machine.u8(Machine.load8(p + i, 0))
    c >= 48 && c <= 57
  end

  # Reads Ruby's decimal Float syntax from `s`: sign, digits with single
  # underscores between them, a fraction (or a bare point after digits),
  # and an exponent. The digits go to `b` without underscores, for
  # strtod. Returns the number of bytes read, or -1 when the text does
  # not start with a number.
  #: (value, ptr) -> word
  def zr_float_scan(s, b)
    p = RString[s].ptr
    n = RString[s].len
    i = 0
    while i < n && (Machine.u8(Machine.load8(p + i, 0)) == 32 || (Machine.u8(Machine.load8(p + i, 0)) >= 9 && Machine.u8(Machine.load8(p + i, 0)) <= 13))
      i += 1
    end
    if i < n && (Machine.u8(Machine.load8(p + i, 0)) == 45 || Machine.u8(Machine.load8(p + i, 0)) == 43)
      zr_buf_byte(b, Machine.u8(Machine.load8(p + i, 0)))
      i += 1
    end
    digits = 0
    while i < n && zr_digit_at(p, i)
      zr_buf_byte(b, Machine.u8(Machine.load8(p + i, 0)))
      digits += 1
      i += 1
      if i + 1 < n && Machine.u8(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
        i += 1
      end
    end
    fraction = 0
    if digits > 0 && i < n && Machine.u8(Machine.load8(p + i, 0)) == 46 && !(i + 1 < n && zr_digit_at(p, i + 1))
      i += 1
    elsif i + 1 < n && Machine.u8(Machine.load8(p + i, 0)) == 46 && zr_digit_at(p, i + 1)
      zr_buf_byte(b, 46)
      i += 1
      while i < n && zr_digit_at(p, i)
        zr_buf_byte(b, Machine.u8(Machine.load8(p + i, 0)))
        fraction += 1
        i += 1
        if i + 1 < n && Machine.u8(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
          i += 1
        end
      end
    end
    if digits == 0 && fraction == 0
      return 0 - 1
    end
    if i < n && (Machine.u8(Machine.load8(p + i, 0)) == 101 || Machine.u8(Machine.load8(p + i, 0)) == 69)
      j = i + 1
      if j < n && (Machine.u8(Machine.load8(p + j, 0)) == 45 || Machine.u8(Machine.load8(p + j, 0)) == 43)
        j += 1
      end
      if j < n && zr_digit_at(p, j)
        zr_buf_byte(b, 101)
        k = i + 1
        while k < j
          zr_buf_byte(b, Machine.u8(Machine.load8(p + k, 0)))
          k += 1
        end
        i = j
        while i < n && zr_digit_at(p, i)
          zr_buf_byte(b, Machine.u8(Machine.load8(p + i, 0)))
          i += 1
          if i + 1 < n && Machine.u8(Machine.load8(p + i, 0)) == 95 && zr_digit_at(p, i + 1)
            i += 1
          end
        end
      end
    end
    i
  end

  # ruby_strtod (missing/dtoa.c) reads at most DBL_DIG * 4 significant
  # digits of a fraction: once it has more than 60 digits, it drops each
  # later digit after the point. Every digit before the point counts, and
  # leading zeros count for nothing. This cuts the number in `b` (the text
  # that zr_float_scan wrote) the same way, so that a long fraction rounds
  # as in ruby and not exactly: the system's strtod reads every digit.
  #: (ptr) -> void
  def zr_float_cut_fraction(b)
    q = Buf[b].ptr
    len = Buf[b].len
    i = 0
    if i < len && (Machine.u8(Machine.load8(q, 0)) == 45 || Machine.u8(Machine.load8(q, 0)) == 43)
      i += 1
    end
    nd = 0
    while i < len && zr_digit_at(q, i)
      if nd > 0 || Machine.u8(Machine.load8(q + i, 0)) != 48
        nd += 1
      end
      i += 1
    end
    if i >= len || Machine.u8(Machine.load8(q + i, 0)) != 46
      return
    end
    i += 1
    zeros = 0
    while i < len && zr_digit_at(q, i)
      if nd > 60
        stop = i
        while stop < len && zr_digit_at(q, stop)
          stop += 1
        end
        zr_memmove(q + i, q + stop, len - stop)
        Buf[b].len = len - (stop - i)
        return
      end
      if Machine.u8(Machine.load8(q + i, 0)) == 48
        zeros += 1
      else
        nd = nd == 0 ? 1 : nd + zeros + 1
        zeros = 0
      end
      i += 1
    end
  end

  #: (ptr) -> f64
  def zr_buf_strtod(b)
    zr_float_cut_fraction(b)
    zr_buf_byte(b, 0)
    d = Libc.strtod(Buf[b].ptr, 0)
    zr_buf_free(b)
    d
  end

  # `String#to_f`: the number at the start of the text, or 0.0.
  #: (value) -> value
  def zr_str_to_f(s)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    n = zr_float_scan(s, b)
    if n < 0
      zr_buf_free(b)
      return zr_float_new(Machine.f64(0))
    end
    zr_float_second_pass(s, n, b)
    zr_float_new(zr_buf_strtod(b))
  end

  # The length of a mantissa that rb_cstr_to_dbl's buffer holds,
  # DBL_DIG * 4.
  FLOAT_MANTISSA_MAX = 60

  # rb_cstr_to_dbl reads the text with strtod, and reads it again when
  # strtod stops before its end (at an underscore or a trailing
  # character, the first `n` bytes being the number). The second pass
  # copies the number into a buffer: leading zeros become one, and the
  # mantissa keeps at most FLOAT_MANTISSA_MAX bytes, so a longer one
  # loses its last digits.
  #: (value, word, ptr) -> void
  def zr_float_second_pass(s, n, b)
    p = RString[s].ptr
    second = n < RString[s].len
    i = 0
    while !second && i < n
      second = Machine.u8(Machine.load8(p + i, 0)) == 95
      i += 1
    end
    unless second
      return
    end
    q = Buf[b].ptr
    len = Buf[b].len
    mantissa = 0
    while mantissa < len && Machine.u8(Machine.load8(q + mantissa, 0)) != 101
      mantissa += 1
    end
    start = mantissa > 0 && (Machine.u8(Machine.load8(q, 0)) == 45 || Machine.u8(Machine.load8(q, 0)) == 43) ? 1 : 0
    zeros = 0
    while start + zeros < mantissa && Machine.u8(Machine.load8(q + start + zeros, 0)) == 48
      zeros += 1
    end
    if zeros > 1
      zr_memmove(q + start + 1, q + start + zeros, len - start - zeros)
      len -= zeros - 1
      mantissa -= zeros - 1
    end
    if mantissa > FLOAT_MANTISSA_MAX
      zr_memmove(q + FLOAT_MANTISSA_MAX, q + mantissa, len - mantissa)
      len -= mantissa - FLOAT_MANTISSA_MAX
    end
    Buf[b].len = len
  end

  # `Float(text)`: all the text, except whitespace, must be a number.
  # Returns nil when it is not. A hex form goes to `zr_hex_to_f`.
  #: (value) -> value
  def zr_str_to_f_strict(s)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    n = zr_float_scan(s, b)
    if n < 0
      zr_buf_free(b)
      return Machine.value(QNIL)
    end
    p = RString[s].ptr
    len = RString[s].len
    if n + 1 < len && (Machine.u8(Machine.load8(p + n, 0)) == 120 || Machine.u8(Machine.load8(p + n, 0)) == 88) && zr_buf_last_is_zero(b)
      zr_buf_free(b)
      return zr_hex_to_f(s)
    end
    while n < len && (Machine.u8(Machine.load8(p + n, 0)) == 32 || (Machine.u8(Machine.load8(p + n, 0)) >= 9 && Machine.u8(Machine.load8(p + n, 0)) <= 13))
      n += 1
    end
    if n != len
      zr_buf_free(b)
      return Machine.value(QNIL)
    end
    zr_float_second_pass(s, zr_float_number_end(s), b)
    zr_float_new(zr_buf_strtod(b))
  end

  # The bytes of `s` that its number spans, before any trailing space.
  #: (value) -> word
  def zr_float_number_end(s)
    p = RString[s].ptr
    n = RString[s].len
    while n > 0 && (Machine.u8(Machine.load8(p + n - 1, 0)) == 32 || (Machine.u8(Machine.load8(p + n - 1, 0)) >= 9 && Machine.u8(Machine.load8(p + n - 1, 0)) <= 13))
      n -= 1
    end
    n
  end

  #: (word) -> bool
  def zr_hex_digit_p(c)
    (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
  end

  # `Float("0x1p+3")`: strtod reads the hex form itself, so all the text
  # goes to it. The end pointer shows whether it read all the text.
  #: (value) -> value
  def zr_hex_to_f(s)
    p = RString[s].ptr
    len = RString[s].len
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    i = 0
    while i < len
      c = Machine.u8(Machine.load8(p + i, 0))
      if c != 95
        zr_buf_byte(b, c)
      elsif i == 0 || i + 1 >= len || !zr_hex_digit_p(Machine.u8(Machine.load8(p + i - 1, 0))) ||
            !zr_hex_digit_p(Machine.u8(Machine.load8(p + i + 1, 0)))
        # An underscore stands only between two digits: not next to the
        # 0x prefix, the p of the exponent, or either end.
        zr_buf_free(b)
        return Machine.value(QNIL)
      end
      i += 1
    end
    zr_buf_byte(b, 0)
    last = Machine.slot(8)
    Machine.store64(last, 0, 0)
    d = Libc.strtod(Buf[b].ptr, last)
    stop = Machine.ptr(Machine.load64(last, 0))
    read = stop == 0 ? 0 : stop - Buf[b].ptr
    while read > 0 && read < Buf[b].len - 1 && (Machine.u8(Machine.load8(Buf[b].ptr + read, 0)) == 32 || (Machine.u8(Machine.load8(Buf[b].ptr + read, 0)) >= 9 && Machine.u8(Machine.load8(Buf[b].ptr + read, 0)) <= 13))
      read += 1
    end
    ok = read > 0 && read == Buf[b].len - 1
    zr_buf_free(b)
    ok ? zr_float_new(d) : Machine.value(QNIL)
  end

  #: (ptr) -> bool
  def zr_buf_last_is_zero(b)
    Buf[b].len > 0 && Machine.u8(Machine.load8(Buf[b].ptr + Buf[b].len - 1, 0)) == 48
  end

  #: (value, value) -> value
  def zr_float_quotient_value(a, b)
    zr_float_new(zr_float_quotient(zr_float_value(a), zr_float_value(b)))
  end

  #: (value) -> value
  def zr_math_sqrt(x)
    zr_float_new(Machine.sqrt(zr_float_value(x)))
  end

  # Math's singleton class, which holds `Math.sqrt` and the others that a
  # site calls directly while GATE_MATH is clear (zr_gates_snapshot).
  G_MATH_META = 63

  # The Math functions that a site `Math.f(x)` calls directly.
  #: (word) -> bool
  def zr_math_inline_p(mid)
    mid == Machine.id(:sqrt) || mid == Machine.id(:cbrt) || mid == Machine.id(:sin) || mid == Machine.id(:cos) ||
      mid == Machine.id(:tan) || mid == Machine.id(:atan) || mid == Machine.id(:exp)
  end

  # `Math.sqrt(x)` for a Float or fixnum `x` in the domain, else nil. It
  # does the send of `check`, the two comparisons and the call of the
  # general path in one function. A zero gives +0.0, as CRuby's math_sqrt
  # does for -0.0.
  #: (value) -> value
  def zr_math_sqrt_fast(x)
    d = Machine.f64(0)
    if zr_fixnum_p(x) && (Machine.gates & GATE_INT_TO_F) == 0
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
  #: (value, value) -> value
  def zr_math_call_fast(which, x)
    if zr_fixnum_p(x) && (Machine.gates & GATE_INT_TO_F) == 0
      return zr_math_call(which, zr_float_new(Machine.to_f64(zr_fix2long(x))), Machine.value(QNIL))
    end
    if zr_fixnum_p(x)
      return Machine.value(QNIL)
    end
    if !zr_float_p(x)
      return Machine.value(QNIL)
    end
    zr_math_call(which, x, Machine.value(QNIL))
  end

  # Calls one libm function, selected by number, on one or two doubles.
  #: (value, value, value) -> value
  def zr_math_call(which, x, y)
    w = zr_fix2long(which)
    a = zr_float_value(x)
    c = Machine.f64(0)
    if zr_float_p(y)
      c = zr_float_value(y)
    end
    if w == 1
      return zr_float_new(Libc.cbrt(a))
    elsif w == 2
      return zr_float_new(Libc.sin(a))
    elsif w == 3
      return zr_float_new(Libc.cos(a))
    elsif w == 4
      return zr_float_new(Libc.tan(a))
    elsif w == 5
      return zr_float_new(Libc.atan(a))
    elsif w == 6
      return zr_float_new(Libc.exp(a))
    elsif w == 7
      return zr_float_new(Libc.atan2(a, c))
    elsif w == 8
      return zr_float_new(Libc.hypot(a, c))
    elsif w == 9
      return zr_float_new(Libc.sinh(a))
    elsif w == 10
      return zr_float_new(Libc.cosh(a))
    elsif w == 11
      return zr_float_new(Libc.tanh(a))
    elsif w == 12
      return zr_float_new(Libc.log(a))
    elsif w == 13
      return zr_float_new(Libc.log2(a))
    elsif w == 14
      return zr_float_new(Libc.log10(a))
    elsif w == 15
      return zr_float_new(Libc.asin(a))
    elsif w == 16
      return zr_float_new(Libc.acos(a))
    elsif w == 17
      return zr_float_new(Libc.asinh(a))
    elsif w == 18
      return zr_float_new(Libc.acosh(a))
    elsif w == 19
      return zr_float_new(Libc.atanh(a))
    elsif w == 20
      return zr_float_new(Libc.tgamma(a))
    elsif w == 21
      return zr_float_new(Libc.erf(a))
    elsif w == 22
      return zr_float_new(Libc.erfc(a))
    elsif w == 23
      return zr_float_new(Libc.ldexp(a, Machine.i32(zr_fix2long(y))))
    elsif w == 24
      return zr_float_new(Libc.expm1(a))
    elsif w == 25
      return zr_float_new(Libc.log1p(a))
    end
    zr_float_new(Libc.lgamma_r(a, Machine.slot(4)))
  end

  # `[mantissa, exponent]` of frexp: the fraction in [0.5, 1) and the
  # power of two.
  #: (value) -> value
  def zr_math_frexp(x)
    e = Machine.slot(4)
    Machine.store32(e, 0, Machine.i32(0))
    m = Libc.frexp(zr_float_value(x), e)
    out = zr_ary_new(2)
    zr_ary_push(out, zr_float_new(m))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(e, 0))))
    out
  end

  # x * y + z with one rounding, as C compilers contract `a * b + c` on
  # arm64 (math.c's `d += numbits * M_LN2`, ruby_float_step's
  # `i * unit + beg`).
  #: (value, value, value) -> value
  def zr_math_fma(x, y, z)
    zr_float_new(Libc.fma(zr_float_value(x), zr_float_value(y), zr_float_value(z)))
  end

  # `[log|gamma|, sign]` of lgamma.
  #: (value) -> value
  def zr_math_lgamma(x)
    s = Machine.slot(4)
    Machine.store32(s, 0, Machine.i32(1))
    v = Libc.lgamma_r(zr_float_value(x), s)
    out = zr_ary_new(2)
    zr_ary_push(out, zr_float_new(v))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(s, 0))))
    out
  end

  # The adjacent double. `up` moves toward +Infinity. From a zero, the
  # result is the smallest subnormal. An infinity does not change, and
  # NaN stays NaN.
  #: (value, word) -> value
  def zr_float_adjacent(recv, up)
    d = zr_float_value(recv)
    if zr_nan_p(d)
      return recv
    end
    # nextafter: an infinity moves only toward zero, to the largest double.
    if zr_inf_p(d) && (d > Machine.f64(0)) == (up != 0)
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

  #: (value, word, ptr, value, value) -> value
  def zr_flo_next_float(recv, argc, argv, cref, blk)
    zr_float_adjacent(recv, 1)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_flo_prev_float(recv, argc, argv, cref, blk)
    zr_float_adjacent(recv, 0)
  end

  # The shortest digits that read back as the same double, and the
  # position of the decimal point: `0.d1d2... * 10^point`.
  #: (value) -> value
  def zr_float_shortest(v)
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
  #: (value) -> value
  def zr_float_halves(v)
    bits = Machine.ptr(Machine.bits(zr_float_value(v)))
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(Machine.word(bits & 4294967295)))
    zr_ary_push(out, zr_fix(Machine.word(bits >> 32)))
    out
  end

  #: (value, value) -> value
  def zr_float_of_halves(low, high)
    zr_float_from_bits(Machine.shl_wrap(zr_fix2long(high), 32) | zr_fix2long(low))
  end

  # CRuby's float_decode_internal: [mantissa, exponent], where the double
  # is mantissa * 2**exponent. The mantissa is a 53-bit Integer (with the
  # sign), so a Rational can contain the exact value.
  #: (value) -> value
  def zr_float_decode(v)
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
end
