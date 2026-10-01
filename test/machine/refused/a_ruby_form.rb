# Array is not in the kernel dialect
module Zr::Kern
  sig [I32, Ptr] => I32
  def main(argc, argv)
    xs = [1, 2]
    0
  end
end
