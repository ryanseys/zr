# The first light of the kernel subset: write and exit through libSystem.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
  end

  #: (i32, ptr) -> i32
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
