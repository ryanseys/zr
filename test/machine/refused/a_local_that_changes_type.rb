# n is already a Word
module Zr::Kern
  Libc.import :exit, [I32] => Void

  sig [I32, Ptr] => I32
  def main(argc, argv)
    n = 1
    n = true
    0
  end
end
