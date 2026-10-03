# The bit tricks: `Machine.ctz`, `clz`, `popcnt` and `bswap`, as wide
# as their operand, a Word or an I32. Every line is a tally ruby can
# check by hand.
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
    while n > 0
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(48 + (n % 10)))
      n = n / 10
    end
    Libc.write(1, buf + at, 24 - at)
  end

  # A loop keeps this def a call, so its answer is no constant to fold.
  #: (word) -> word
  def same(w)
    k = 0
    while k < 1
      k = k + 1
    end
    w
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    # 4 + 64 + 63 + 64 = 195
    put_word(Machine.ctz(same(80)) + Machine.ctz(same(0)) + Machine.clz(same(1)) + Machine.clz(same(0)))
    # An I32 widens first: 9 + 32 + (64 - 32) + 0 = 73
    put_word(Machine.popcnt(same(Machine.word(0xF0F0000000000001))) + Machine.popcnt(Machine.u32(Machine.i32(same(-1)))) +
             (Machine.clz(Machine.u32(Machine.i32(same(0)))) - 32) + Machine.ctz(Machine.u32(Machine.i32(same(1)))))
    # 0x0102030405060708 turned round is 0x0807060504030201
    put_word(Machine.bswap(same(0x0102030405060708)))
    # 0x01020304 widened and turned round, then shifted down: 0x04030201 = 67305985
    put_word(Machine.bswap(Machine.u32(Machine.i32(same(0x01020304)))) >> 32)
    # folded: 3 + 60 + 4 + 1 = 68
    put_word(Machine.ctz(8) + Machine.clz(15) + Machine.popcnt(0xF) + Machine.bswap(0x0100000000000000))
    Libc.exit(0)
    0
  end
end
