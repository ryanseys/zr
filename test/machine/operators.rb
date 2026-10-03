# Every integer operator of the kernel subset, one bit of the exit status each.
module Zr::Kern
  Libc.import :exit, [I32] => Void
  #: (i32, ptr) -> i32
  def main(argc, argv)
    a = 100
    b = 7
    x = a / b
    y = a % b
    z = a * b
    s = a << 3
    t = a >> 2
    u = a ^ b
    code = 0
    if x != 14
      code = code | 1
    end
    if y != 2
      code = code | 2
    end
    if z != 700
      code = code | 4
    end
    if s != 800
      code = code | 8
    end
    if t != 25
      code = code | 16
    end
    if u != 99
      code = code | 32
    end
    n = 0 - 7
    if n / 2 != 0 - 3
      code = code | 64
    end
    if n % 2 != 0 - 1
      code = code | 128
    end
    Libc.exit(Machine.i32(code))
    0
  end
end
