# Integer: fixnums only, for now. Compiled code inlines the fixnum fast
# path of each operator below while its gate bit is clear; a redefinition
# sets the bit (see zr_define_method) and every site takes the call.
GATE_PLUS = 1
GATE_MINUS = 2
GATE_MUL = 4
GATE_DIV = 8
GATE_MOD = 16
GATE_LT = 32
GATE_LE = 64
GATE_GT = 128
GATE_GE = 256
GATE_EQ = 512
GATE_NE = 1024
GATE_NOT = 2048
GATE_AREF = 4096
GATE_ASET = 8192

sig [] => Ptr
machine def zr_gates
  Machine.static(:gates, 8)
end

# The decimal digits of `n` into `buf`, answering how many bytes they
# take, ahead of a buffer of 24.
sig [Word, Ptr] => Word
machine def zr_long_digits(n, buf)
  neg = n < 0
  at = 24
  if n == 0
    at -= 1
    Machine.store8(buf + at, 0, Machine.i8(48))
  end
  while n != 0
    at -= 1
    d = n % 10
    if d < 0
      d = 0 - d
    end
    Machine.store8(buf + at, 0, Machine.i8(48 + d))
    n = n / 10
  end
  if neg
    at -= 1
    Machine.store8(buf + at, 0, Machine.i8(45))
  end
  zr_memcpy(buf, buf + at, 24 - at)
  24 - at
end

# `Integer#to_s(base = 10)`: digits in any base from 2 to 36.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_to_s(recv, argc, argv, cref, blk)
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
  base = 10
  if argc == 1
    out = Machine.slot(8)
    r = zr_int_operand(argv, out)
    return r if r == QUNDEF
    base = Machine.load64(out, 0)
    if base < 2 || base > 36
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("invalid radix "), 14)
      zr_buf_long(b, base)
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
  end
  if base == 10
    buf = Machine.slot(24)
    n = zr_long_digits(zr_fix2long(recv), buf)
    return zr_str_new(buf, n)
  end
  v = zr_fix2long(recv)
  negative = v < 0
  if negative
    v = 0 - v
  end
  buf = Machine.slot(72)
  at = 72
  if v == 0
    at -= 1
    Machine.store8(buf + at, 0, Machine.i8(48))
  end
  while v > 0
    d = v % base
    at -= 1
    Machine.store8(buf + at, 0, Machine.i8(d < 10 ? 48 + d : 87 + d))
    v /= base
  end
  if negative
    at -= 1
    Machine.store8(buf + at, 0, Machine.i8(45))
  end
  zr_str_new(buf + at, 72 - at)
end

# The operand of an Integer operator into `out`, which must be an
# Integer until coercion and Float exist; else the TypeError, raised.
sig [Ptr, Ptr] => Value
machine def zr_int_operand(argv, out)
  other = Machine.value(Machine.load64(argv, 0))
  unless zr_fixnum_p(other)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if zr_special_p(other)
      s = zr_send(other, Machine.id(:inspect), 0, 0)
      return s if s == QUNDEF
      zr_buf_str(b, s)
    else
      zr_buf_str(b, zr_class_name_of(other))
    end
    zr_buf_push(b, Machine.bytes(" can't be coerced into Integer"), 30)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.store64(out, 0, zr_fix2long(other))
  Machine.value(QNIL)
end

# A result outside the fixnum range: bignums are not implemented yet,
# and a wrong answer must not slip out.
sig [Word] => Value
machine def zr_int_result(n)
  if n > 4611686018427387903 || n < 0 - 4611686018427387904
    zr_bug(Machine.bytes("Integer overflow: bignums are not implemented yet\n"), 50)
  end
  zr_fix(n)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_plus(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_int_result(zr_fix2long(recv) + b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_minus(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_int_result(zr_fix2long(recv) - b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_mul(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  p = a * b
  if a != 0 && p / a != b
    zr_bug(Machine.bytes("Integer overflow: bignums are not implemented yet\n"), 50)
  end
  zr_int_result(p)
end

# Floored division and modulo, as Ruby defines them; the caller has
# ruled out a zero divisor.
sig [Word, Word] => Word
machine def zr_floor_div(a, b)
  q = a / b
  if (a % b != 0) && ((a < 0) != (b < 0))
    q -= 1
  end
  q
end

sig [Word, Word] => Word
machine def zr_floor_mod(a, b)
  a - (zr_floor_div(a, b) * b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_div(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12) if b == 0
  zr_int_result(zr_floor_div(zr_fix2long(recv), b))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_mod(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12) if b == 0
  zr_fix(zr_floor_mod(zr_fix2long(recv), b))
end

# The bit operators; a shift past 62 bits leaves the fixnum range and
# stops loudly until bignums arrive.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_and(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  zr_fix(zr_fix2long(recv) & Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_or(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  zr_fix(zr_fix2long(recv) | Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_xor(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  zr_fix(zr_fix2long(recv) ^ Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_not(recv, argc, argv, cref, blk)
  zr_fix(0 - zr_fix2long(recv) - 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_lshift(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  n = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  if n < 0
    return zr_fix(a >> (0 - n))
  end
  if n >= 62 || (a != 0 && ((a << n) >> n) != a)
    zr_bug(Machine.bytes("a shift past the fixnum range needs bignums\n"), 44)
  end
  zr_int_result(a << n)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_rshift(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  n = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  if n < 0
    if (0 - n) >= 62
      zr_bug(Machine.bytes("a shift past the fixnum range needs bignums\n"), 44)
    end
    return zr_int_result(a << (0 - n))
  end
  if n >= 63
    return zr_fix(a < 0 ? 0 - 1 : 0)
  end
  zr_fix(a >> n)
end

sig [Bool] => Value
machine def zr_bool(b)
  if b
    Machine.value(QTRUE)
  else
    Machine.value(QFALSE)
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_lt(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) < b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_le(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) <= b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_gt(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) > b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_ge(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) >= b)
end

# Equality takes any operand: a non-Integer is simply not equal.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_eq(recv, argc, argv, cref, blk)
  zr_bool(recv == Machine.value(Machine.load64(argv, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_ne(recv, argc, argv, cref, blk)
  zr_bool(recv != Machine.value(Machine.load64(argv, 0)))
end
