# exit wants a I32 here, not a Word
module Zr::Kern
  Libc.import :exit, [I32] => Void

  sig [I32, Ptr] => I32
  def main(argc, argv)
    code = 3
    Libc.exit(code)
    0
  end
end
