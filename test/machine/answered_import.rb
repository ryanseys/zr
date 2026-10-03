# A def of an imported name answers that import's calls: `exit` here
# says goodbye before it leaves through `_exit`.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void
  Libc.import :_exit, [I32] => Void

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
