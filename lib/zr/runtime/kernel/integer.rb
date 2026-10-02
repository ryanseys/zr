module Zr::Kern
  # Integer builtins for fixnums. A bignum goes to the core library.
  # Compiled code inlines the fixnum fast path of each operator below while
  # its gate bit is clear. A redefinition sets the bit (see
  # zr_define_method), and then every site makes the call. The gate word is
  # in its own register. `Machine.gates` reads it, `Machine.gates_set`
  # writes it and its static, and `Machine.gates_enter` loads it from the
  # static where foreign code enters.
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
  # The named calls that have their own fast path (zr_opt_getbyte and the
  # others). Their bits are above the operator bits, in the same word.
  GATE_GETBYTE = 1 << 31
  GATE_SETBYTE = 1 << 32
  GATE_SUCC = 1 << 33
  GATE_PUSH = 1 << 34
  GATE_POP = 1 << 35
  GATE_SHIFT = 1 << 36
  GATE_EMPTY_P = 1 << 37
  # Proc#call on a `&b` parameter that is bound to the block that the
  # caller gave (zr_opt_block_call).
  GATE_PROC_CALL = 1 << 38
  # `is_a?`, `kind_of?` and `instance_of?` from Kernel, for every object.
  # These two gates close when any class defines a method of that name,
  # because a site gets the result from the receiver's class only.
  GATE_IS_A = 1 << 39
  GATE_INSTANCE_OF = 1 << 40
  # Symbol#===: a `case` whose `when` values are all symbol literals
  # compares the subject with each symbol by identity
  # (Function::Control#symbol_case). A `case` arm on a class does not use
  # a gate for Module#===. Its cache entry records whether `===` is
  # Module's. A gate cannot see SystemCallError's own `===`, because the
  # core defines it before the program starts.
  GATE_SYM_EQQ = 1 << 41
  # `nil?` from Kernel and NilClass. The gate closes when any class
  # defines a method of that name, because a site gets the result from
  # the receiver only.
  GATE_NIL_P = 1 << 42
  # Array#each, Integer#times and Range#each. A site with a block literal
  # runs the loop inline while each method is the original of its class
  # (Function::Iterators).
  GATE_EACH = 1 << 43
  GATE_TIMES = 1 << 44
  GATE_RANGE_EACH = 1 << 45
  # Integer#-@ and Float#-@: a site negates a fixnum or a flonum inline.
  GATE_UMINUS = 1 << 46
  GATE_FLO_UMINUS = 1 << 47
  # Integer#<=>: the core library compares two fixnums natively while it
  # is ruby's own, as CRuby's OPTIMIZED_CMP does.
  GATE_CMP = 1 << 48
  # Array#map and Array#select: a site with a block literal runs the
  # loop inline, and pushes to the new Array there (Function::Iterators).
  GATE_MAP = 1 << 49
  GATE_SELECT = 1 << 50

  # Writes the decimal digits of `n` into `buf` and returns the number of
  # bytes. `buf` must have 24 bytes.
  sig [Word, Ptr] => Word
  def zr_long_digits(n, buf)
    neg = n < 0
    at = 24
    if n == 0
      at -= 1
      Machine.store8(buf + at, 0, Machine.i8(48))
    end
    while n != 0
      at -= 1
      d = Machine.srem(n, 10)
      if d < 0
        d = 0 - d
      end
      Machine.store8(buf + at, 0, Machine.i8(48 + d))
      n = Machine.sdiv(n, 10)
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
  def zr_int_to_s(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:to_s), argc, argv)
    end
    if argc > 1
      return zr_wrong_arity_range(argc, 0, 1)
    end
    base = 10
    if argc == 1
      # As NUM2INT: nil is not a radix, and a Float truncates to an Integer.
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

  # A bignum is a plain object of class Integer. Its limbs are in hidden
  # instance variables, and its arithmetic is in the core library
  # (`Integer#big_op`). Every fixnum builtin sends the operation there when
  # one operand is a bignum.
  sig [Value] => Bool
  def zr_big_p(v)
    !zr_special_p(v) && zr_type(v) == T_OBJECT && RBasic.klass(v) == zr_global(G_INTEGER)
  end

  # Makes an empty bignum object for the core to fill.
  sig [] => Value
  def zr_big_alloc
    zr_obj_alloc(zr_global(G_INTEGER))
  end

  sig [Value] => Value
  def zr_fixnum_p_m(v)
    zr_bool(zr_fixnum_p(v))
  end

  # An integer literal outside the fixnum range. The first time its site
  # runs, the core parses its decimal digits. A table keeps the Integer at
  # the site's index, and later runs return the same Integer.
  G_BIG_LITERALS = 54

  sig [Word, Ptr, Word] => Value
  def zr_big_literal(index, bytes, n)
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

  # Calls `recv.big_op(:mid, *argv)` with the builtin's block.
  sig [Value, Word, Word, Ptr, Value] => Value
  def zr_big_route_blk(recv, mid, argc, argv, blk)
    args = zr_xmalloc((argc + 1) * 8)
    Machine.store64(args, 0, Machine.word(zr_sym(mid)))
    zr_memcpy(args + 8, argv, argc * 8)
    r = zr_send_blk(recv, Machine.id(:big_op), argc + 1, args, blk)
    zr_xfree(args)
    r
  end

  sig [Value, Word, Word, Ptr] => Value
  def zr_big_route(recv, mid, argc, argv)
    zr_big_route_blk(recv, mid, argc, argv, Machine.value(QNIL))
  end

  # Converts a machine word that can be outside the fixnum range. Returns
  # a fixnum when it fits. If not, `Integer.big_from_word(high, low)` makes
  # a bignum from its two halves.
  sig [Word] => Value
  def zr_int_from_word(n)
    if n <= 4611686018427387903 && n >= 0 - 4611686018427387904
      return zr_fix(n)
    end
    pair = Machine.slot(16)
    Machine.store64(pair, 0, Machine.word(zr_fix(n >> 32)))
    Machine.store64(pair, 8, Machine.word(zr_fix(n & 4294967295)))
    zr_send(zr_global(G_INTEGER), Machine.id(:big_from_word), 2, pair)
  end

  # Writes a shift count into `out`. A bignum goes to the core. Any other
  # value converts through to_int (a Float truncates), as rb_to_int does.
  sig [Value, Ptr, Ptr, Word] => Value
  def zr_shift_operand(recv, argv, out, mid)
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

  # Writes the operand of an Integer operator into `out` when it is an
  # Integer, and returns QNIL. If not, `kind` gives the result: 0 sends
  # `mid` through `other.coerce(recv)`, 1 raises the comparison failure,
  # 2 returns nil, and 3 raises only the TypeError.
  sig [Value, Ptr, Ptr, Word, Word] => Value
  def zr_int_operand(recv, argv, out, mid, kind)
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

  # CRuby's rb_num_coerce_bin / relop / cmp. `other.coerce(recv)` returns
  # [a, b], and the operator runs as `a mid b`. If `other` has no coerce,
  # `kind` decides: 0 and 3 raise the TypeError, 1 raises the comparison
  # failure, and 2 returns nil.
  sig [Value, Value, Word, Word] => Value
  def zr_num_coerce(recv, other, mid, kind)
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
        # A bit operator (`kind` 4) accepts only Integers, as CRuby's
        # bit_coerce checks. Any other result fails as the operand fails.
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
    # The message shows a Float (heap or not) with inspect, as CRuby's
    # coerce_failed and rb_cmperr do. It shows any other value by its class.
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

  # `zr_num_coerce` for the core. The operator is a Symbol and the kind is
  # an Integer.
  sig [Value, Value, Value, Value] => Value
  def zr_num_coerce_m(recv, other, mid, kind)
    zr_num_coerce(recv, other, zr_sym2id(mid), zr_fix2long(kind))
  end

  # Returns an arithmetic result. A result outside the fixnum range
  # becomes a bignum (zr_int_from_word).
  sig [Word] => Value
  def zr_int_result(n)
    zr_int_from_word(n)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_plus(recv, argc, argv, cref, blk)
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
  def zr_int_minus(recv, argc, argv, cref, blk)
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
  def zr_int_mul(recv, argc, argv, cref, blk)
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
    p = Machine.mul_wrap(a, b)
    if a != 0 && Machine.sdiv(p, a) != b
      return zr_big_route(recv, Machine.id(:*), 1, argv)
    end
    zr_int_result(p)
  end

  # Floored division and modulo, as Ruby defines them. The caller must
  # make sure that the divisor is not zero.
  sig [Word, Word] => Word
  def zr_floor_div(a, b)
    q = Machine.sdiv(a, b)
    if (Machine.srem(a, b) != 0) && ((a < 0) != (b < 0))
      q -= 1
    end
    q
  end

  sig [Word, Word] => Word
  def zr_floor_mod(a, b)
    a - (zr_floor_div(a, b) * b)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_div(recv, argc, argv, cref, blk)
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
  def zr_int_mod(recv, argc, argv, cref, blk)
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

  # The bit operators. A left shift that leaves the fixnum range goes to
  # the core's bignum code.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_and(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:&), argc, argv)
    end
    out = Machine.slot(8)
    r = zr_int_operand(recv, argv, out, Machine.id(:&), 4)
    return r if r != QNIL
    zr_fix(zr_fix2long(recv) & Machine.load64(out, 0))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_or(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:|), argc, argv)
    end
    out = Machine.slot(8)
    r = zr_int_operand(recv, argv, out, Machine.id(:|), 4)
    return r if r != QNIL
    zr_fix(zr_fix2long(recv) | Machine.load64(out, 0))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_xor(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:^), argc, argv)
    end
    out = Machine.slot(8)
    r = zr_int_operand(recv, argv, out, Machine.id(:^), 4)
    return r if r != QNIL
    zr_fix(zr_fix2long(recv) ^ Machine.load64(out, 0))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_not(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:~), argc, argv)
    end
    zr_fix(0 - zr_fix2long(recv) - 1)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_lshift(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:<<), argc, argv)
    end
    out = Machine.slot(8)
    r = zr_shift_operand(recv, argv, out, Machine.id(:<<))
    return r if r != QNIL
    n = Machine.load64(out, 0)
    a = zr_fix2long(recv)
    if n < 0
      # The hardware uses the shift count mod 64, but ruby shifts all bits
      # out.
      if (0 - n) >= 63
        return zr_fix(a < 0 ? 0 - 1 : 0)
      end
      return zr_fix(a >> (0 - n))
    end
    # `a << n` fits in a word when the bits that it shifts out, and the
    # new sign bit, are all copies of the sign: all 0 or all 1.
    top = a >> (63 - n) if n < 62
    if n >= 62 || (top != 0 && top != 0 - 1)
      return zr_big_route(recv, Machine.id(:<<), 1, argv)
    end
    zr_int_result(a << n)
  end

  # `Integer#bit_length` of a fixnum: the number of bits after the sign.
  # This is the position of the highest set bit of `n` (of `-n - 1` when
  # `n` is negative).
  sig [Value] => Value
  def zr_fix_bit_length(v)
    n = zr_fix2long(v)
    if n < 0
      n = 0 - n - 1
    end
    if n == 0
      return zr_fix(0)
    end
    zr_fix(64 - Machine.clz(n))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_rshift(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route(recv, Machine.id(:>>), argc, argv)
    end
    out = Machine.slot(8)
    r = zr_shift_operand(recv, argv, out, Machine.id(:>>))
    return r if r != QNIL
    n = Machine.load64(out, 0)
    a = zr_fix2long(recv)
    if n < 0
      # As in zr_int_lshift: the bits shifted out and the new sign bit
      # must all be copies of the sign.
      top = a >> (63 + n) if n > 0 - 62
      if (0 - n) >= 62 || (top != 0 && top != 0 - 1)
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
  def zr_bool(b)
    if b
      Machine.value(QTRUE)
    else
      Machine.value(QFALSE)
    end
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_lt(recv, argc, argv, cref, blk)
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
  def zr_int_le(recv, argc, argv, cref, blk)
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
  def zr_int_gt(recv, argc, argv, cref, blk)
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
  def zr_int_ge(recv, argc, argv, cref, blk)
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

  # Equality accepts any operand. A Float compares exactly, and any other
  # non-Integer is not equal.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_int_eq(recv, argc, argv, cref, blk)
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

  # Compares an Integer with a double exactly. Returns -1, 0, 1, or 2 for
  # NaN. If the integer part of the double does not fit a fixnum, its sign
  # gives the result.
  sig [Word, F64] => Word
  def zr_int_float_cmp(n, d)
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
  def zr_int_float_relate(n, d, want)
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

  # `Integer#<=>` with a Float. Returns nil for NaN.
  sig [Value, Value] => Value
  def zr_int_float_spaceship(recv, other)
    c = zr_int_float_cmp(zr_fix2long(recv), zr_float_value(other))
    if c == 2
      return Machine.value(QNIL)
    end
    zr_fix(c)
  end
end
