# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.

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
    zr_capi_long_of(v, true)
  end

  # rb_big2long and rb_big2ll: a bignum that fits.
  #: (value) -> word
  def rb_big2long(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_long_of(v, false)
  end

  #: (value) -> word
  def rb_big2ll(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_long_of(v, true)
  end

  #: (value) -> word
  def zr_capi_long(v)
    zr_capi_long_of(v, false)
  end

  # A long, or a long long when `ll`, which only the messages tell apart.
  #: (value, bool) -> word
  def zr_capi_long_of(v, ll)
    while true
      if v == QNIL
        zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("no implicit conversion of nil into Integer"), 42)
      end
      if zr_fixnum_p(v)
        return zr_fix2long(v)
      end
      if zr_float_p(v)
        d = zr_float_value(v)
        if d < Machine.f64(F64_TWO_63) && d >= Machine.f64(0) - Machine.f64(F64_TWO_63)
          return Machine.to_int(Machine.trunc(d))
        end
        zr_capi_float_range(v, ll ? 1 : 0)
      end
      if zr_big_p(v)
        out = Machine.slot(8)
        if !zr_big_to_long(v, out)
          if ll
            zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'long long'"), 42)
          end
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
    zr_capi_ulong_of(v, false)
  end

  #: (value) -> word
  def rb_num2ull(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_ulong_of(v, true)
  end

  # rb_big2ulong and rb_big2ull: a bignum that fits, a negative one
  # wrapped.
  #: (value) -> word
  def rb_big2ulong(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_big_ulong(v, false)
  end

  #: (value) -> word
  def rb_big2ull(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_big_ulong(v, true)
  end

  # rb_big_sign: 1 for a bignum of 0 or more, else 0.
  #: (value) -> i32
  def rb_big_sign(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_negative_p(v) ? Machine.i32(0) : Machine.i32(1)
  end

  # rb_num2uint and rb_fix2uint: an unsigned long that an unsigned int
  # holds, or a negative one that an int holds, as check_uint allows.
  #: (value) -> word
  def rb_num2uint(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_uint(zr_capi_ulong_of(v, false), zr_capi_negative_p(v))
  end

  #: (value) -> word
  def rb_fix2uint(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_uint(zr_capi_ulong_of(v, false), zr_capi_negative_p(v))
  end

  # rb_absint_size: the bytes of `v`'s magnitude, and in `*nlz` the zero
  # bits at the top of the last byte.
  #: (value, ptr) -> word
  def rb_absint_size(v, nlz)
    Machine.gates_enter
    zr_c_entered()
    magnitude = zr_c_result(zr_send(v, Machine.id(:abs), 0, Machine.ptr(0)))
    bits = zr_fix2long(zr_c_result(zr_send(magnitude, Machine.id(:bit_length), 0, Machine.ptr(0))))
    bytes = (bits + 7) / 8
    if nlz != 0
      Machine.store32(nlz, 0, Machine.i32((bytes * 8) - bits))
    end
    bytes
  end

  # rb_absint_numwords: the words of `word_numbits` bits that `v`'s
  # magnitude takes, and in `*nlz` the zero bits at the top of the last
  # one; (size_t)-1 for words of no bits.
  #: (value, word, ptr) -> word
  def rb_absint_numwords(v, word_numbits, nlz)
    Machine.gates_enter
    zr_c_entered()
    if word_numbits == 0
      return 0 - 1
    end
    magnitude = zr_c_result(zr_send(v, Machine.id(:abs), 0, Machine.ptr(0)))
    bits = zr_fix2long(zr_c_result(zr_send(magnitude, Machine.id(:bit_length), 0, Machine.ptr(0))))
    words = bits / word_numbits
    rest = bits % word_numbits
    if rest != 0
      words += 1
    end
    if nlz != 0
      Machine.store64(nlz, 0, rest == 0 ? 0 : word_numbits - rest)
    end
    words
  end

  # Whether the Integer or Float `v` is below 0.
  #: (value) -> bool
  def zr_capi_negative_p(v)
    if zr_fixnum_p(v)
      return zr_fix2long(v) < 0
    end
    if zr_float_p(v)
      return zr_float_value(v) < Machine.f64(0)
    end
    zr_big_p(v) && zr_hidden_get(v, zr_sym(Machine.id(:__neg__))) == QTRUE
  end

  # check_uint's RangeError.
  #: (word, bool) -> word
  def zr_capi_check_uint(n, negative)
    if negative ? n >= 0 - 2147483648 : Machine.ptr(n) <= Machine.ptr(4294967295)
      return n
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("integer "), 8)
    if negative
      zr_buf_long(b, n)
      zr_buf_push(b, Machine.bytes(" too small to convert to 'unsigned int'"), 39)
    else
      zr_buf_str(b, zr_c_result(zr_obj_as_string(zr_capi_unsigned(n))))
      zr_buf_push(b, Machine.bytes(" too big to convert to 'unsigned int'"), 37)
    end
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
    n
  end

  # An unsigned long, or an unsigned long long when `ll`.
  #: (value, bool) -> word
  def zr_capi_ulong_of(v, ll)
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
        zr_capi_float_range(v, ll ? 2 : 0)
      end
      if zr_big_p(v)
        return zr_capi_big_ulong(v, ll)
      end
      v = zr_c_result(zr_to_int(v))
    end
    0
  end

  # A bignum as an unsigned long (an unsigned long long when `ll`): its
  # magnitude below 2^64, negated (wrapping) when the bignum is negative
  # and its magnitude is at most 2^63, as rb_big2ulong gives it.
  #: (value, bool) -> word
  def zr_capi_big_ulong(v, ll)
    out = Machine.slot(8)
    if zr_big_to_long(v, out)
      return Machine.load64(out, 0)
    end
    limbs = zr_hidden_get(v, zr_sym(Machine.id(:__limbs__)))
    neg = zr_hidden_get(v, zr_sym(Machine.id(:__neg__))) == QTRUE
    n = RArray[limbs].len
    top = n == 3 ? zr_fix2long(zr_ary_at(limbs, 2)) : 0
    if n > 3 || top >= 16
      if ll
        zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'unsigned long long'"), 51)
      end
      zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum too big to convert into 'unsigned long'"), 46)
    end
    magnitude = Machine.shl_wrap(top, 60) | Machine.shl_wrap(zr_fix2long(zr_ary_at(limbs, 1)), 30) | zr_fix2long(zr_ary_at(limbs, 0))
    if !neg
      return magnitude
    end
    # Past 2^63, a negative magnitude has no unsigned long.
    if ll
      zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum out of range of unsigned long long"), 41)
    end
    zr_c_raise(zr_core_class(Machine.id(:RangeError)), Machine.bytes("bignum out of range of unsigned long"), 36)
    0
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

  # rb_num2dbl: an Integer or a Float as a double. A String, or a special
  # constant that is no number, has no implicit conversion; Float() takes
  # them.
  #: (value) -> f64
  def rb_num2dbl(v)
    Machine.gates_enter
    zr_c_entered()
    if zr_float_p(v)
      return zr_float_value(v)
    end
    if (zr_special_p(v) && !zr_fixnum_p(v)) || (!zr_special_p(v) && zr_type(v) == T_STRING)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      zr_buf_cname(b, v)
      zr_buf_push(b, Machine.bytes(" into Float"), 11)
      zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
    end
    # rb_convert_type_with_id: an object with no to_f cannot convert.
    if !zr_fixnum_p(v) && zr_c_result(zr_check_funcall(v, Machine.id(:to_f))) != QTRUE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't convert "), 14)
      zr_buf_cname(b, v)
      zr_buf_push(b, Machine.bytes(" into Float"), 11)
      zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
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
  # with the Float as `%-.10g` gives it. rb_num2ll and rb_num2ull name
  # their C type instead (`kind` 1 and 2).
  #: (value, word) -> void
  def zr_capi_float_range(v, kind)
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_str_new(Machine.bytes("%-.10g"), 6)))
    Machine.store64(argv, 8, Machine.word(v))
    text = zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:format), 2, argv))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("float "), 6)
    zr_buf_str(b, text)
    if kind == 1
      zr_buf_push(b, Machine.bytes(" out of range of long long"), 26)
    elsif kind == 2
      zr_buf_push(b, Machine.bytes(" out of range of unsigned long long"), 35)
    else
      zr_buf_push(b, Machine.bytes(" out of range of integer"), 24)
    end
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
  end

  # rb_out_of_int: the RangeError of a long that is not an int.
  #: (word) -> void
  def rb_out_of_int(n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_int(n)
  end

  # rb_out_of_long: the RangeError of a number that is not a long, which
  # rb_len2long raises where rb_len_t is wider than long.
  #: (word) -> void
  def rb_out_of_long(n)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("integer "), 8)
    zr_buf_long(b, n)
    if n < 0
      zr_buf_push(b, Machine.bytes(" too small to convert to 'long'"), 31)
    else
      zr_buf_push(b, Machine.bytes(" too big to convert to 'long'"), 29)
    end
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
  end

  # rb_big2str: `x.to_s(base)`.
  #: (value, i32) -> value
  def rb_big2str(x, base)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:to_s), zr_fix(Machine.sword(base)))
  end

  # rb_complex_new: the Complex `real + imag i`, as Complex.rect makes it.
  #: (value, value) -> value
  def rb_complex_new(real, imag)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(real))
    Machine.store64(args, 8, Machine.word(imag))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Complex)), Machine.id(:rect), 2, args))
  end

  # rb_rational_new: the Rational `num / den`, reduced.
  #: (value, value) -> value
  def rb_rational_new(num, den)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(num))
    Machine.store64(args, 8, Machine.word(den))
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:Rational), 2, args))
  end

  # rb_to_float: `v` as a Float. A Float is itself, and any other
  # Numeric gives its `to_f`. Any other value cannot convert: CRuby's
  # TypeError names nil, true and false, and the class of the rest.
  #: (value) -> value
  def rb_to_float(v)
    Machine.gates_enter
    zr_c_entered()
    if zr_float_p(v)
      return v
    end
    if !zr_is_a(v, zr_core_class(Machine.id(:Numeric)))
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't convert "), 14)
      shown = v == QNIL || v == QTRUE || v == QFALSE ? v : zr_real_class(v)
      zr_buf_str(b, zr_c_result(zr_inspect(shown)))
      zr_buf_push(b, Machine.bytes(" into Float"), 11)
      zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
    end
    f = zr_c_result(zr_send(v, Machine.id(:to_f), 0, Machine.ptr(0)))
    zr_capi_converted(v, f, T_FLOAT, Machine.bytes("Float"), 5, Machine.id(:to_f))
  end

  # rb_big_norm: a bignum in its smallest form; zr's Integers are always
  # in it.
  #: (value) -> value
  def rb_big_norm(x)
    Machine.gates_enter
    zr_c_entered()
    x
  end

  # rb_big2dbl: the Float nearest the Integer `x`, as a double.
  #: (value) -> f64
  def rb_big2dbl(x)
    Machine.gates_enter
    zr_c_entered()
    zr_float_value(zr_c_result(zr_send(x, Machine.id(:to_f), 0, Machine.ptr(0))))
  end

  # rb_big_cmp, rb_big_plus, rb_big_minus, rb_big_mul, rb_big_div,
  # rb_big_modulo, rb_big_pow and rb_big_eq: the Integer operators, for an
  # `x` that C knows to be a bignum.
  #: (value, value) -> value
  def rb_big_cmp(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:<=>), y)
  end

  #: (value, value) -> value
  def rb_big_plus(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:+), y)
  end

  #: (value, value) -> value
  def rb_big_minus(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:-), y)
  end

  #: (value, value) -> value
  def rb_big_mul(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:*), y)
  end

  #: (value, value) -> value
  def rb_big_div(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:/), y)
  end

  #: (value, value) -> value
  def rb_big_modulo(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:%), y)
  end

  #: (value, value) -> value
  def rb_big_pow(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:**), y)
  end

  #: (value, value) -> value
  def rb_big_eq(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(x, Machine.id(:==), y)
  end

  # rb_dbl2big: the Integer of the double `d`, truncated.
  #: (f64) -> value
  def rb_dbl2big(d)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_float_new(d), Machine.id(:to_i), 0, Machine.ptr(0)))
  end

  # rb_num_coerce_bin: `x id y` after `y.coerce(x)`, as a numeric
  # operator does for an operand it does not know.
  #: (value, value, word) -> value
  def rb_num_coerce_bin(x, y, id)
    Machine.gates_enter
    zr_c_entered()
    # do_coerce with err: no coerce is coerce_failed's TypeError, and a
    # coerce must give a pair.
    if zr_c_result(zr_check_funcall(y, Machine.id(:coerce))) != QTRUE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      if zr_special_p(y)
        zr_buf_str(b, zr_c_result(zr_inspect(y)))
      else
        zr_buf_class(b, zr_real_class(y))
      end
      zr_buf_push(b, Machine.bytes(" can't be coerced into "), 23)
      zr_buf_class(b, zr_real_class(x))
      zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
    end
    pair = zr_capi_call1(y, Machine.id(:coerce), x)
    if zr_special_p(pair) || zr_type(pair) != T_ARRAY || RArray[pair].len != 2
      zr_c_result(zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("coerce must return [x, y]"), 25))
    end
    zr_capi_call1(zr_ary_at(pair, 0), zr_capi_mid(id), zr_ary_at(pair, 1))
  end

  # rb_num_coerce_relop: the same for a comparison. No coerce, or a coerce
  # that gives nil, is CRuby's "coercion was not possible"; an answer of
  # nil is its "comparator returned nil".
  #: (value, value, word) -> value
  def rb_num_coerce_relop(x, y, id)
    Machine.gates_enter
    zr_c_entered()
    pair = Machine.value(QNIL)
    if zr_c_result(zr_check_funcall(y, Machine.id(:coerce))) == QTRUE
      pair = zr_capi_call1(y, Machine.id(:coerce), x)
    end
    if pair == QNIL
      zr_c_result(zr_cmperr_coerce(x, y))
    end
    r = zr_capi_call1(zr_ary_at(pair, 0), zr_capi_mid(id), zr_ary_at(pair, 1))
    if r == QNIL
      zr_c_result(zr_cmperr(x, y))
    end
    r
  end

  # rb_num_coerce_cmp: `x id y` after `y.coerce(x)`, or nil when `y`
  # has no coerce or its coerce gives nil, as a comparison of a number
  # with what it does not know answers.
  #: (value, value, word) -> value
  def rb_num_coerce_cmp(x, y, id)
    Machine.gates_enter
    zr_c_entered()
    if zr_c_result(zr_check_funcall(y, Machine.id(:coerce))) != QTRUE
      return Machine.value(QNIL)
    end
    pair = zr_capi_call1(y, Machine.id(:coerce), x)
    if pair == QNIL
      return Machine.value(QNIL)
    end
    zr_capi_call1(zr_ary_at(pair, 0), zr_capi_mid(id), zr_ary_at(pair, 1))
  end

  # rb_int_positive_pow: the Integer `x ** y` for a C long and an
  # unsigned long.
  #: (word, word) -> value
  def rb_int_positive_pow(x, y)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_int_from_word(x), Machine.id(:**), zr_capi_unsigned(y))
  end

  # rb_Rational: `Rational(num, den)`, which converts and raises as the
  # Kernel method does.
  #: (value, value) -> value
  def rb_Rational(num, den)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(num))
    Machine.store64(args, 8, Machine.word(den))
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:Rational), 2, args))
  end

  # rb_complex_real and rb_complex_imag: a Complex's parts.
  #: (value) -> value
  def rb_complex_real(z)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(z, Machine.id(:real), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_complex_imag(z)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(z, Machine.id(:imaginary), 0, Machine.ptr(0)))
  end

  # rb_rational_num and rb_rational_den: a Rational's numerator and
  # denominator.
  #: (value) -> value
  def rb_rational_num(rat)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(rat, Machine.id(:numerator), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_rational_den(rat)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(rat, Machine.id(:denominator), 0, Machine.ptr(0)))
  end

  # rb_num2short, rb_fix2short and rb_num2ushort: an Integer as a C
  # short, with CRuby's RangeError past it.
  #: (value) -> i32
  def rb_num2short(v)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_short_of(v, 0 - 32768, 32767, Machine.bytes("short"), 5))
  end

  #: (value) -> i32
  def rb_fix2short(v)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_short_of(v, 0 - 32768, 32767, Machine.bytes("short"), 5))
  end

  #: (value) -> i32
  def rb_num2ushort(v)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_short_of(v, 0 - 32768, 65535, Machine.bytes("unsigned short"), 14) & 65535)
  end

  #: (value, word, word, ptr, word) -> word
  def zr_capi_short_of(v, low, high, cname, clen)
    n = zr_capi_long(v)
    if n < low || n > high
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("integer "), 8)
      zr_buf_long(b, n)
      zr_buf_push(b, n < low ? Machine.bytes(" too small to convert to '") : Machine.bytes(" too big to convert to '"), n < low ? 26 : 24)
      zr_buf_push(b, cname, clen)
      zr_buf_byte(b, 39)
      zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
    end
    n
  end

  # rb_integer_pack's and rb_integer_unpack's flags (INTEGER_PACK_*): the
  # order of the words and of the bytes in a word, two's complement, and
  # a negative magnitude.
  INTEGER_PACK_MSWORD_FIRST = 0x01
  INTEGER_PACK_MSBYTE_FIRST = 0x10
  INTEGER_PACK_2COMP = 0x80
  INTEGER_PACK_NEGATIVE = 0x200

  # rb_integer_pack: the Integer `val` into `numwords` words of `wordsize`
  # bytes at `words`, in the order that `flags` gives: its magnitude, or
  # its two's complement under INTEGER_PACK_2COMP. Returns its sign (-1,
  # 0 or 1), or twice it when the words cannot hold it. zr packs whole
  # bytes: `nails` must be 0.
  #: (value, ptr, word, word, word, i32) -> i32
  def rb_integer_pack(val, words, numwords, wordsize, nails, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_no_nails(nails)
    f = Machine.sword(flags)
    n = zr_capi_to_int(val)
    sign = zr_fix2long(zr_capi_call1(n, Machine.id(:<=>), zr_fix(0)))
    total = numwords * wordsize
    room = zr_capi_call1(zr_fix(1), Machine.id(:<<), zr_fix(total * 8))
    magnitude = zr_c_result(zr_send(n, Machine.id(:abs), 0, Machine.ptr(0)))
    if (f & INTEGER_PACK_2COMP) != 0 && sign < 0
      magnitude = zr_capi_call1(room, Machine.id(:-), magnitude)
    end
    fits = zr_capi_call1(magnitude, Machine.id(:<), room) == QTRUE
    digits = zr_capi_call1(zr_capi_call1(magnitude, Machine.id(:%), room), Machine.id(:digits), zr_fix(256))
    i = 0
    while i < total
      byte = i < RArray[digits].len ? zr_fix2long(zr_ary_at(digits, i)) : 0
      Machine.store8(zr_capi_packed_at(words, i, numwords, wordsize, f), 0, Machine.i8(byte))
      i += 1
    end
    Machine.i32(fits ? sign : sign * 2)
  end

  # rb_integer_unpack: the Integer in the `numwords` words of `wordsize`
  # bytes at `words`, read in the order that `flags` gives: a magnitude,
  # negative under INTEGER_PACK_NEGATIVE, or a two's complement under
  # INTEGER_PACK_2COMP.
  #: (ptr, word, word, word, i32) -> value
  def rb_integer_unpack(words, numwords, wordsize, nails, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_no_nails(nails)
    f = Machine.sword(flags)
    total = numwords * wordsize
    digits = zr_ary_new(total)
    i = 0
    while i < total
      zr_ary_push(digits, zr_fix(Machine.u8(Machine.load8(zr_capi_packed_at(words, i, numwords, wordsize, f), 0))))
      i += 1
    end
    n = zr_capi_from_digits(digits)
    if (f & INTEGER_PACK_2COMP) != 0 && total > 0 && (zr_fix2long(zr_ary_at(digits, total - 1)) & 128) != 0
      return zr_capi_call1(n, Machine.id(:-), zr_capi_call1(zr_fix(1), Machine.id(:<<), zr_fix(total * 8)))
    end
    (f & INTEGER_PACK_NEGATIVE) != 0 ? zr_c_result(zr_send(n, Machine.id(:-@), 0, Machine.ptr(0))) : n
  end

  # The address of the byte of significance `i` (0 the least) of the
  # packed words: the word and the byte within it in the order of `flags`
  # (native byte order is little-endian here).
  #: (ptr, word, word, word, word) -> ptr
  def zr_capi_packed_at(words, i, numwords, wordsize, flags)
    w = i / wordsize
    b = i % wordsize
    if (flags & INTEGER_PACK_MSWORD_FIRST) != 0
      w = numwords - 1 - w
    end
    if (flags & INTEGER_PACK_MSBYTE_FIRST) != 0
      b = wordsize - 1 - b
    end
    words + ((w * wordsize) + b)
  end

  # The Integer of the base-256 `digits`, the least significant first.
  #: (value) -> value
  def zr_capi_from_digits(digits)
    bytes = zr_capi_call1(zr_c_result(zr_send(digits, Machine.id(:reverse), 0, Machine.ptr(0))), Machine.id(:pack),
                          zr_str_new(Machine.bytes("C*"), 2))
    hex = zr_capi_call1(bytes, Machine.id(:unpack1), zr_str_new(Machine.bytes("H*"), 2))
    zr_capi_call1(hex, Machine.id(:to_i), zr_fix(16))
  end

  #: (word) -> void
  def zr_capi_no_nails(nails)
    if nails != 0
      zr_c_raise(zr_core_class(Machine.id(:NotImplementedError)), Machine.bytes("zr packs no nails"), 17)
    end
  end
end
