# Integer: fixnums only, for now.

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

sig [Value, Word, Ptr] => Value
machine def zr_int_to_s(recv, argc, argv)
  buf = Machine.slot(24)
  n = zr_long_digits(zr_fix2long(recv), buf)
  zr_str_new(buf, n)
end
