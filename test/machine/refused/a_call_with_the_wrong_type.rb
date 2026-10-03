# exit wants a I32 here, not a Word
module Zr::Kern
  Libc.import :exit, [I32] => Void

  #: (i32, ptr) -> i32
  def main(argc, argv)
    code = 3
    Libc.exit(code)
    0
  end
end
