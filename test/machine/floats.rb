# F64 in the kernel subset: arithmetic, comparison and the conversions,
# printed as integers.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void

  #: (word) -> void
  def put_word(n)
    buf = Machine.slot(24)
    at = 23
    Machine.store8(buf + at, 0, Machine.i8(10))
    if n == 0
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(48))
    end
    neg = n < 0
    if neg
      n = 0 - n
    end
    while n > 0
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(48 + (n % 10)))
      n = n / 10
    end
    if neg
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(45))
    end
    Libc.write(1, buf + at, 24 - at)
  end

  #: (f64, f64) -> f64
  def average(a, b)
    (a + b) / Machine.to_f64(2)
  end

  #: (bool) -> word
  def flag(b)
    b ? 1 : 0
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    one_and_half = Machine.f64(4609434218613702656)
    x = (one_and_half + Machine.f64(4612248968380809216)) * Machine.to_f64(2)
    put_word(Machine.to_int(x * Machine.to_f64(100)))
    put_word(Machine.to_int(Machine.floor(Machine.to_f64(0) - one_and_half)))
    put_word(Machine.to_int(Machine.ceil(one_and_half)))
    put_word(Machine.to_int(Machine.nearest(Machine.f64(4612248968380809216))))
    put_word(Machine.to_int(Machine.sqrt(Machine.to_f64(144))))
    put_word(Machine.to_int(Machine.fabs(-x)))
    put_word(Machine.bits(Machine.to_f64(1)))
    put_word(Machine.to_int(average(Machine.to_f64(3), Machine.to_f64(4)) * Machine.to_f64(10)))
    nan = Machine.f64(9221120237041090560)
    put_word(flag(nan == nan) + (flag(nan != nan) * 10) + (flag(one_and_half < x) * 100) + (flag(x <= one_and_half) * 1000) + (flag(nan < x) * 10000))
    put_word(Machine.to_int(Machine.trunc(Machine.to_f64(0) - Machine.f64(4612248968380809216))))
    Libc.exit(0)
    0
  end
end
