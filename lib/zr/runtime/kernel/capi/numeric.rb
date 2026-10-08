module Zr::Kern
  # The C API's numbers. FIX2LONG, INT2FIX and the flonum tests are
  # inline in an extension; these are the calls that NUM2LONG, LONG2NUM
  # and the rest make for the other cases. Each raises as CRuby's
  # numeric.c and bignum.c do, with their messages.

  # 2^63 and 2^64 as doubles: the bounds of a Float that a long and an
  # unsigned long take (LONG_MAX_PLUS_ONE, ULONG_MAX_PLUS_ONE).
  F64_TWO_63 = 4890909195324358656
  F64_TWO_64 = 4895412794951729152

  # rb_num2long: an Integer, a Float that fits, or what to_int gives, as a
  # long.
  #: (value) -> word
  def rb_num2long(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_long(v)
  end

  # rb_num2ll: the same, for a long long, which is a long here.
  #: (value) -> word
  def rb_num2ll(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_long(v)
  end

  #: (value) -> word
  def zr_capi_long(v)
    while true
      if v == QNIL
        zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("no implicit conversion from nil to integer"), 42)
      end
      if zr_fixnum_p(v)
        return zr_fix2long(v)
      end
      if zr_float_p(v)
        d = zr_float_value(v)
        if d < Machine.f64(F64_TWO_63) && d >= Machine.f64(0) - Machine.f64(F64_TWO_63)
          return Machine.to_int(Machine.trunc(d))
        end
        zr_capi_float_range(v)
      end
      if zr_big_p(v)
        out = Machine.slot(8)
        if !zr_big_to_long(v, out)
          zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'long'"), 37)
        end
        return Machine.load64(out, 0)
      end
      v = zr_c_result(zr_to_int(v))
    end
    0
  end

  # rb_num2ulong: an Integer as an unsigned long. A negative one wraps,
  # as a C cast does.
  #: (value) -> word
  def rb_num2ulong(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ulong(v)
  end

  #: (value) -> word
  def rb_num2ull(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ulong(v)
  end

  #: (value) -> word
  def zr_capi_ulong(v)
    while true
      if v == QNIL
        zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("no implicit conversion of nil into Integer"), 42)
      end
      if zr_fixnum_p(v)
        return zr_fix2long(v)
      end
      if zr_float_p(v)
        d = zr_float_value(v)
        if d < Machine.f64(F64_TWO_64) && d >= Machine.f64(0) - Machine.f64(F64_TWO_63)
          if d >= Machine.f64(F64_TWO_63)
            return Machine.to_int(Machine.trunc(d - Machine.f64(F64_TWO_63))) | Machine.word(0x8000000000000000)
          end
          return Machine.to_int(Machine.trunc(d))
        end
        zr_capi_float_range(v)
      end
      if zr_big_p(v)
        return zr_capi_big_ulong(v)
      end
      v = zr_c_result(zr_to_int(v))
    end
    0
  end

  # A bignum as an unsigned long: its magnitude below 2^64, negated
  # (wrapping) when the bignum is negative, as rb_big2ulong gives it.
  #: (value) -> word
  def zr_capi_big_ulong(v)
    out = Machine.slot(8)
    if zr_big_to_long(v, out)
      return Machine.load64(out, 0)
    end
    limbs = zr_hidden_get(v, zr_sym(Machine.id(:__limbs__)))
    neg = zr_hidden_get(v, zr_sym(Machine.id(:__neg__))) == QTRUE
    n = RArray[limbs].len
    top = n == 3 ? zr_fix2long(zr_ary_at(limbs, 2)) : 0
    if n > 3 || top >= 16
      zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum out of range of unsigned long"), 36)
    end
    magnitude = Machine.shl_wrap(top, 60) | Machine.shl_wrap(zr_fix2long(zr_ary_at(limbs, 1)), 30) | zr_fix2long(zr_ary_at(limbs, 0))
    neg ? Machine.sub_wrap(0, magnitude) : magnitude
  end

  # rb_num2int and rb_fix2int: as rb_num2long, then within an int.
  #: (value) -> word
  def rb_num2int(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_int(zr_capi_long(v))
  end

  #: (value) -> word
  def rb_fix2int(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_int(zr_capi_long(v))
  end

  # rb_out_of_int's RangeError for a long that is not an int.
  #: (word) -> word
  def zr_capi_check_int(n)
    if n >= 0 - 2147483648 && n <= 2147483647
      return n
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("integer "), 8)
    zr_buf_long(b, n)
    if n < 0
      zr_buf_push(b, Machine.bytes(" too small to convert to 'int'"), 30)
    else
      zr_buf_push(b, Machine.bytes(" too big to convert to 'int'"), 28)
    end
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
    n
  end

  # rb_num2dbl: an Integer or a Float as a double. A String or nil is a
  # TypeError, as Float() is not.
  #: (value) -> f64
  def rb_num2dbl(v)
    Machine.gates_enter
    zr_c_entered()
    if zr_float_p(v)
      return zr_float_value(v)
    end
    if v == QNIL || v == QTRUE || v == QFALSE || (!zr_special_p(v) && zr_type(v) == T_STRING)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion to float from "), 37)
      if v == QNIL
        zr_buf_push(b, Machine.bytes("nil"), 3)
      elsif v == QTRUE
        zr_buf_push(b, Machine.bytes("true"), 4)
      elsif v == QFALSE
        zr_buf_push(b, Machine.bytes("false"), 5)
      else
        zr_buf_push(b, Machine.bytes("string"), 6)
      end
      zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
    end
    zr_float_value(zr_c_result(zr_send(v, Machine.id(:to_f), 0, Machine.slot(8))))
  end

  # rb_int2big (and rb_int2inum, LONG2NUM's call): a long as an Integer.
  #: (word) -> value
  def rb_int2big(n)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_int_from_word(n))
  end

  #: (word) -> value
  def rb_int2inum(n)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_int_from_word(n))
  end

  #: (word) -> value
  def rb_ll2inum(n)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_int_from_word(n))
  end

  # rb_uint2big (and rb_uint2inum, rb_ull2inum): an unsigned long as an
  # Integer.
  #: (word) -> value
  def rb_uint2big(n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_unsigned(n)
  end

  #: (word) -> value
  def rb_uint2inum(n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_unsigned(n)
  end

  #: (word) -> value
  def rb_ull2inum(n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_unsigned(n)
  end

  # The Integer of the unsigned 64 bits `n`. Past 2^63 the top half is
  # taken as unsigned, so `Integer.big_from_word` makes a positive one.
  #: (word) -> value
  def zr_capi_unsigned(n)
    if n >= 0
      return zr_c_result(zr_int_from_word(n))
    end
    pair = Machine.slot(16)
    Machine.store64(pair, 0, Machine.word(zr_fix((n >> 32) & 4294967295)))
    Machine.store64(pair, 8, Machine.word(zr_fix(n & 4294967295)))
    zr_c_result(zr_send(zr_global(G_INTEGER), Machine.id(:big_from_word), 2, pair))
  end

  # rb_float_new (DBL2NUM): a double as a Float.
  #: (f64) -> value
  def rb_float_new(d)
    Machine.gates_enter
    zr_c_entered()
    zr_float_new(d)
  end

  # rb_float_value (RFLOAT_VALUE): a Float's double.
  #: (value) -> f64
  def rb_float_value(v)
    Machine.gates_enter
    zr_c_entered()
    zr_float_value(v)
  end

  # FLOAT_OUT_OF_RANGE's RangeError: `float 1e+20 out of range of integer`,
  # with the Float as `%-.10g` gives it.
  #: (value) -> void
  def zr_capi_float_range(v)
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_str_new(Machine.bytes("%-.10g"), 6)))
    Machine.store64(argv, 8, Machine.word(v))
    text = zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:format), 2, argv))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("float "), 6)
    zr_buf_str(b, text)
    zr_buf_push(b, Machine.bytes(" out of range of integer"), 24)
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
  end
end
