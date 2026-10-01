# The first light of the kernel dialect: write and exit through libSystem.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void

  sig [I32, Ptr] => I32
  def main(argc, argv)
    msg = Machine.bytes("hello, zr!\n")
    n = 0
    while n < 3
      Libc.write(1, msg, 11)
      n += 1
    end
    Libc.exit(0)
    0
  end
end
