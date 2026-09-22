# Integer: fixnums only, for now. Compiled code inlines the fixnum fast
# path of each operator below while its gate bit is clear; a redefinition
# sets the bit (see zr_define_method) and every site takes the call. The
# gate word lives in a register of its own, read by `Machine.gates`,
# written with its static by `Machine.gates_set`, and loaded from the
# static where foreign code enters (`Machine.gates_enter`).
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
GATE_AND = 65536
GATE_OR = 131072
GATE_XOR = 262144
GATE_SHR = 524288
GATE_HASH_AREF = 1048576
GATE_HASH_ASET = 2097152
# The named calls with a fast path of their own (zr_opt_getbyte and
# the rest): bits above the operators', in the same word.
GATE_GETBYTE = 1 << 31
GATE_SETBYTE = 1 << 32
GATE_SUCC = 1 << 33
GATE_PUSH = 1 << 34
GATE_POP = 1 << 35
GATE_SHIFT = 1 << 36
GATE_EMPTY_P = 1 << 37
# Proc#call, for a `&b` parameter bound as the block it was given
# (zr_opt_block_call).
GATE_PROC_CALL = 1 << 38
# `is_a?`, `kind_of?` and `instance_of?`, Kernel's for every object:
# these two close when a method of the name is defined anywhere,
# since a site answers them by the receiver's class alone.
GATE_IS_A = 1 << 39
GATE_INSTANCE_OF = 1 << 40
# Module#===, what `case obj when Mod` asks: closes when `===` is
# defined on a class's or module's singleton class, or on Module,
# Class, Object, Kernel or BasicObject, which every such receiver
# finds it through.
GATE_MOD_EQQ = 1 << 41

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
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:to_s), argc, argv)
  end
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
  base = 10
  if argc == 1
    # NUM2INT: nil is no radix, and a Float truncates to one.
    out = Machine.slot(8)
    r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
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
    return zr_usascii_str_new(buf, n)
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
  zr_usascii_str_new(buf + at, 72 - at)
end

# A bignum is a plain object of class Integer: its limbs live in
# hidden instance variables and its arithmetic in the core library
# (`Integer#big_op`). Every fixnum builtin routes there when either
# side is one.
sig [Value] => Bool
machine def zr_big_p(v)
  !zr_special_p(v) && zr_type(v) == T_OBJECT && RBasic.klass(v) == zr_global(G_INTEGER)
end

# A fresh bignum shell for the core to fill.
sig [] => Value
machine def zr_big_alloc
  zr_obj_alloc(zr_global(G_INTEGER))
end

sig [Value] => Value
machine def zr_fixnum_p_m(v)
  zr_bool(zr_fixnum_p(v))
end

# A literal past the fixnum range: its decimal digits, parsed by the
# core the first time its site runs, then the same Integer, held in a
# table by the site's index.
G_BIG_LITERALS = 54

sig [Word, Ptr, Word] => Value
machine def zr_big_literal(index, bytes, n)
  big = zr_site_literal(G_BIG_LITERALS, index)
  if big != QNIL
    return big
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(zr_str_new(bytes, n)))
  big = zr_send(zr_global(G_INTEGER), Machine.id(:big_parse), 1, slot)
  return big if big == QUNDEF
  zr_site_literal_set(G_BIG_LITERALS, index, big)
  big
end

# `recv.big_op(:mid, *argv)`, with the builtin's block.
sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_big_route_blk(recv, mid, argc, argv, blk)
  args = zr_xmalloc((argc + 1) * 8)
  Machine.store64(args, 0, Machine.word(zr_sym(mid)))
  zr_memcpy(args + 8, argv, argc * 8)
  r = zr_send_blk(recv, Machine.id(:big_op), argc + 1, args, blk)
  zr_xfree(args)
  r
end

sig [Value, Word, Word, Ptr] => Value
machine def zr_big_route(recv, mid, argc, argv)
  zr_big_route_blk(recv, mid, argc, argv, Machine.value(QNIL))
end

# A machine word that may lie past the fixnum range: a fixnum when it
# fits, else the bignum `Integer.big_from_word(high, low)` builds from
# its two halves.
sig [Word] => Value
machine def zr_int_from_word(n)
  if n <= 4611686018427387903 && n >= 0 - 4611686018427387904
    return zr_fix(n)
  end
  pair = Machine.slot(16)
  Machine.store64(pair, 0, Machine.word(zr_fix(n >> 32)))
  Machine.store64(pair, 8, Machine.word(zr_fix(n & 4294967295)))
  zr_send(zr_global(G_INTEGER), Machine.id(:big_from_word), 2, pair)
end

# A shift count into `out`: a bignum routes, anything else converts
# through to_int (a Float truncates), as rb_to_int does.
sig [Value, Ptr, Ptr, Word] => Value
machine def zr_shift_operand(recv, argv, out, mid)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_fixnum_p(other) || zr_big_p(other)
    return zr_int_operand(recv, argv, out, mid, 0)
  end
  if other == QNIL
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("no implicit conversion of nil into Integer"), 42)
  end
  if zr_float_p(other)
    count = Machine.slot(8)
    Machine.store64(count, 0, Machine.word(zr_send(other, Machine.id(:to_int), 0, 0)))
    return Machine.value(QUNDEF) if Machine.value(Machine.load64(count, 0)) == QUNDEF
    return zr_int_operand(recv, count, out, mid, 0)
  end
  zr_index_operand(other, out)
end

# The operand of an Integer operator into `out` when it is an Integer;
# else the answer of `other.coerce(recv)` sent `mid` (`kind` 0), or the
# comparison failure (`kind` 1), or nil (`kind` 2), or the TypeError
# alone (`kind` 3). QNIL means the operand is in `out`.
sig [Value, Ptr, Ptr, Word, Word] => Value
machine def zr_int_operand(recv, argv, out, mid, kind)
  other = Machine.value(Machine.load64(argv, 0))
  unless zr_fixnum_p(other)
    if zr_big_p(other)
      return zr_big_route(recv, mid, 1, argv)
    end
    return zr_num_coerce(recv, other, mid, kind)
  end
  Machine.store64(out, 0, zr_fix2long(other))
  Machine.value(QNIL)
end

# CRuby's rb_num_coerce_bin / relop / cmp: `other.coerce(recv)` answers
# [a, b], and the operator runs as `a mid b`. Without a coerce, `kind`
# decides: 0 and 3 raise the TypeError, 1 the comparison failure, 2
# answers nil.
sig [Value, Value, Word, Word] => Value
machine def zr_num_coerce(recv, other, mid, kind)
  if kind != 3 && !zr_special_p(other)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(Machine.value(zr_sym(Machine.id(:coerce)))))
    responds = zr_send(other, Machine.id(:respond_to?), 1, slot)
    return responds if responds == QUNDEF
    if responds != QNIL && responds != QFALSE
      Machine.store64(slot, 0, Machine.word(recv))
      pair = zr_send(other, Machine.id(:coerce), 1, slot)
      return pair if pair == QUNDEF
      if zr_special_p(pair) || zr_type(pair) != T_ARRAY || RArray.len(pair) != 2
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("coerce must return [x, y]"), 25)
      end
      first = zr_ary_at(pair, 0)
      second = zr_ary_at(pair, 1)
      # A bit operator (`kind` 4) takes Integers alone, as CRuby's
      # bit_coerce checks: anything else fails as the operand does.
      if kind != 4 || ((zr_fixnum_p(first) || zr_big_p(first)) && (zr_fixnum_p(second) || zr_big_p(second)))
        Machine.store64(slot, 0, Machine.word(second))
        return zr_send(first, mid, 1, slot)
      end
    end
  end
  if kind == 2
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if kind == 1
    zr_buf_push(b, Machine.bytes("comparison of "), 14)
    zr_buf_class_of(b, recv)
    zr_buf_push(b, Machine.bytes(" with "), 6)
  end
  # A Float shows by inspect, heap or not, as CRuby's coerce_failed
  # and rb_cmperr name it; anything else by its class.
  if zr_special_p(other) || zr_float_p(other)
    s = zr_inspect(other)
    return s if s == QUNDEF
    zr_buf_str(b, s)
  else
    zr_buf_class_of(b, other)
  end
  if kind == 1
    zr_buf_push(b, Machine.bytes(" failed"), 7)
    return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end
  zr_buf_push(b, Machine.bytes(" can't be coerced into "), 23)
  zr_buf_class_of(b, recv)
  zr_raise_buf(zr_global(G_TYPE_ERROR), b)
end

# `zr_num_coerce` for the core: the operator as a Symbol, the kind as
# an Integer.
sig [Value, Value, Value, Value] => Value
machine def zr_num_coerce_m(recv, other, mid, kind)
  zr_num_coerce(recv, other, zr_sym2id(mid), zr_fix2long(kind))
end

# A result outside the fixnum range: bignums are not implemented yet,
# and a wrong answer must not slip out.
sig [Word] => Value
machine def zr_int_result(n)
  zr_int_from_word(n)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_plus(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:+), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_float_new(Machine.to_f64(zr_fix2long(recv)) + zr_float_value(Machine.value(Machine.load64(argv, 0))))
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:+), 0)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_int_result(zr_fix2long(recv) + b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_minus(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:-), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_float_new(Machine.to_f64(zr_fix2long(recv)) - zr_float_value(Machine.value(Machine.load64(argv, 0))))
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:-), 0)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_int_result(zr_fix2long(recv) - b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_mul(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:*), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_float_new(Machine.to_f64(zr_fix2long(recv)) * zr_float_value(Machine.value(Machine.load64(argv, 0))))
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:*), 0)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  p = a * b
  if a != 0 && p / a != b
    return zr_big_route(recv, Machine.id(:*), 1, argv)
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
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:/), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_float_new(Machine.to_f64(zr_fix2long(recv)) / zr_float_value(Machine.value(Machine.load64(argv, 0))))
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:/), 0)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12) if b == 0
  zr_int_result(zr_floor_div(zr_fix2long(recv), b))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_mod(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:%), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    y = zr_float_value(Machine.value(Machine.load64(argv, 0)))
    if y == Machine.f64(0)
      return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12)
    end
    return zr_float_new(zr_float_mod(Machine.to_f64(zr_fix2long(recv)), y))
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:%), 0)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  return zr_raise_msg(zr_global(G_ZERO_DIVISION_ERROR), Machine.bytes("divided by 0"), 12) if b == 0
  zr_fix(zr_floor_mod(zr_fix2long(recv), b))
end

# The bit operators; a shift past 62 bits leaves the fixnum range and
# stops loudly until bignums arrive.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_and(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:&), argc, argv)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:&), 4)
  return r if r != QNIL
  zr_fix(zr_fix2long(recv) & Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_or(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:|), argc, argv)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:|), 4)
  return r if r != QNIL
  zr_fix(zr_fix2long(recv) | Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_xor(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:^), argc, argv)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:^), 4)
  return r if r != QNIL
  zr_fix(zr_fix2long(recv) ^ Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_not(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:~), argc, argv)
  end
  zr_fix(0 - zr_fix2long(recv) - 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_lshift(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:<<), argc, argv)
  end
  out = Machine.slot(8)
  r = zr_shift_operand(recv, argv, out, Machine.id(:<<))
  return r if r != QNIL
  n = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  if n < 0
    # The hardware takes a shift count mod 64; ruby shifts every bit out.
    if (0 - n) >= 63
      return zr_fix(a < 0 ? 0 - 1 : 0)
    end
    return zr_fix(a >> (0 - n))
  end
  if n >= 62 || (a != 0 && ((a << n) >> n) != a)
    return zr_big_route(recv, Machine.id(:<<), 1, argv)
  end
  zr_int_result(a << n)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_rshift(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:>>), argc, argv)
  end
  out = Machine.slot(8)
  r = zr_shift_operand(recv, argv, out, Machine.id(:>>))
  return r if r != QNIL
  n = Machine.load64(out, 0)
  a = zr_fix2long(recv)
  if n < 0
    if (0 - n) >= 62 || (a != 0 && ((a << (0 - n)) >> (0 - n)) != a)
      return zr_big_route(recv, Machine.id(:>>), 1, argv)
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
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:<), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_int_float_relate(zr_fix2long(recv), zr_float_value(Machine.value(Machine.load64(argv, 0))), 0)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:<), 1)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) < b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_le(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:<=), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_int_float_relate(zr_fix2long(recv), zr_float_value(Machine.value(Machine.load64(argv, 0))), 1)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:<=), 1)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) <= b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_gt(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:>), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_int_float_relate(zr_fix2long(recv), zr_float_value(Machine.value(Machine.load64(argv, 0))), 2)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:>), 1)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) > b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_ge(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:>=), argc, argv)
  end
  if zr_float_p(Machine.value(Machine.load64(argv, 0)))
    return zr_int_float_relate(zr_fix2long(recv), zr_float_value(Machine.value(Machine.load64(argv, 0))), 3)
  end
  out = Machine.slot(8)
  r = zr_int_operand(recv, argv, out, Machine.id(:>=), 1)
  return r if r != QNIL
  b = Machine.load64(out, 0)
  zr_bool(zr_fix2long(recv) >= b)
end

# Equality takes any operand: a Float compares exactly, and a
# non-Integer is simply not equal.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_eq(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:==), argc, argv)
  end
  other = Machine.value(Machine.load64(argv, 0))
  if zr_float_p(other)
    return zr_bool(zr_int_float_cmp(zr_fix2long(recv), zr_float_value(other)) == 0)
  end
  if zr_fixnum_p(other) || zr_special_p(other)
    return zr_bool(recv == other)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(other, Machine.id(:==), 1, slot)
  return r if r == QUNDEF
  zr_bool(r != QNIL && r != QFALSE)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_ne(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route(recv, Machine.id(:!=), argc, argv)
  end
  other = Machine.value(Machine.load64(argv, 0))
  if zr_float_p(other)
    return zr_bool(zr_int_float_cmp(zr_fix2long(recv), zr_float_value(other)) != 0)
  end
  if zr_fixnum_p(other) || zr_special_p(other)
    return zr_bool(recv != other)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(other, Machine.id(:==), 1, slot)
  return r if r == QUNDEF
  zr_bool(r == QNIL || r == QFALSE)
end

# An Integer against a double, exactly: -1, 0, 1, or 2 for NaN. The
# double's integer part fits a fixnum, or its sign alone decides.
sig [Word, F64] => Word
machine def zr_int_float_cmp(n, d)
  if zr_nan_p(d)
    return 2
  end
  if d >= Machine.f64(4886405595696988160)
    return 0 - 1
  end
  if d <= -Machine.f64(4886405595696988160)
    return 1
  end
  t = Machine.trunc(d)
  ti = Machine.to_int(t)
  if n < ti
    return 0 - 1
  end
  if n > ti
    return 1
  end
  if d > t
    return 0 - 1
  end
  if d < t
    return 1
  end
  0
end

sig [Word, F64, Word] => Value
machine def zr_int_float_relate(n, d, want)
  c = zr_int_float_cmp(n, d)
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

# `Integer#<=>` with a Float: nil for NaN.
sig [Value, Value] => Value
machine def zr_int_float_spaceship(recv, other)
  c = zr_int_float_cmp(zr_fix2long(recv), zr_float_value(other))
  if c == 2
    return Machine.value(QNIL)
  end
  zr_fix(c)
end

sig [Value] => Value
machine def zr_float_check_p(v)
  zr_bool(zr_float_p(v))
end
