# rescue and ensure are not in the kernel subset
module Zr::Kern
  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
ensure
  1
end
