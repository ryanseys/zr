# a condition that is a Void
module Zr::Kern
  Libc.import :exit, [I32] => Void

  sig [I32, Ptr] => I32
  def main(argc, argv)
    if Libc.exit(0) && true
      1
    end
    0
  end
end
