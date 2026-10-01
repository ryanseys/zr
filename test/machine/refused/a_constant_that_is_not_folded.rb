# a constant is an integer, a constant, a struct's size, or an operator over those
module Zr::Kern
  LIMIT = Machine.load64(Machine.slot(8), 0)

  sig [I32, Ptr] => I32
  def main(argc, argv)
    0
  end
end
