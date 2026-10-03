# A def of an imported name answers that import's calls: `exit` here
# says goodbye before it leaves through `_exit`.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
    #: (i32) -> void
    def self._exit(i) = Machine.import
  end

  #: (i32) -> void
  def exit(code)
    Libc.write(1, Machine.bytes("bye\n"), 4)
    Libc._exit(code)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    Libc.write(1, Machine.bytes("hi\n"), 3)
    Libc.exit(0)
    0
  end
end
