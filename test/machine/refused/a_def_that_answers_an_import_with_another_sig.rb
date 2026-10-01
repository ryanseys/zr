# exit answers an import of [I32] => Void, and its sig differs
module Zr::Kern
  Libc.import :exit, [I32] => Void

  sig [Word] => Void
  def exit(code)
  end

  sig [I32, Ptr] => I32
  def main(argc, argv)
    0
  end
end
