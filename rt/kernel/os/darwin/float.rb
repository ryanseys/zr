# darwin's libm and libc reach for floats: cos and sin of a multiple of
# pi, and the decimal digits of a double.
Machine.import "__cospi", [F64] => F64
Machine.import "__sinpi", [F64] => F64
Machine.import "fcvt", [F64, I32, Ptr, Ptr] => Ptr
Machine.import "ecvt", [F64, I32, Ptr, Ptr] => Ptr

# cos(pi * x) and sin(pi * x).
sig [F64] => F64
machine def zr_os_cospi(x)
  __cospi(x)
end

sig [F64] => F64
machine def zr_os_sinpi(x)
  __sinpi(x)
end

# The correctly rounded decimal digits of a double, as libSystem's
# fcvt (`ndigit` past the point) or ecvt (`ndigit` in all) give them:
# the digit string, the position of the point, and the sign.
sig [Value, Value, Value] => Value
machine def zr_os_float_digits(v, ndigit, fixed)
  d = zr_float_value(v)
  decpt = Machine.slot(8)
  sign = Machine.slot(8)
  p = fixed == QTRUE ? fcvt(d, Machine.i32(zr_fix2long(ndigit)), decpt, sign) : ecvt(d, Machine.i32(zr_fix2long(ndigit)), decpt, sign)
  out = zr_ary_new(3)
  zr_ary_push(out, zr_str_new(p, zr_cstr_len(p)))
  point = Machine.word(Machine.load32(decpt, 0))
  if point >= 2147483648
    point -= 4294967296
  end
  zr_ary_push(out, zr_fix(point))
  zr_ary_push(out, zr_bool(Machine.word(Machine.load32(sign, 0)) != 0))
  out
end
