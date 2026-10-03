# Array is not in the kernel subset
module Zr::Kern
  #: (i32, ptr) -> i32
  def main(argc, argv)
    xs = [1, 2]
    0
  end
end
