# The d registers of the aarch64 backend: a float operation whose first
# operand is in a d register keeps it when the load of its second
# operand takes the next register in the rotation. Here `a` is in the
# first register of the rotation, and the load of the constant comes back
# to that register.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
  end

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

  # Each line after the sum takes one more register of the rotation, so
  # the constant of the last product is loaded when the rotation is back
  # at the register of `a`.
  #: (f64, f64) -> f64
  def rotation(a, b)
    c = a + b
    d = c * c
    e = d * d
    f = e * e
    g = f * f
    h = g * g
    r = a * Machine.f64(0x4008000000000000) # 3.0
    r + (h * Machine.f64(0))
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    # 2.0 * 3.0, not 3.0 * 3.0
    put_word(Machine.to_int(rotation(Machine.f64(0x4000000000000000), Machine.f64(0x3FF0000000000000))))
    Libc.exit(0)
    0
  end
end
