# exit answers an import of [I32] => Void, and its sig differs
module Zr::Kern
  Libc.import :exit, [I32] => Void

  #: (word) -> void
  def exit(code)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
