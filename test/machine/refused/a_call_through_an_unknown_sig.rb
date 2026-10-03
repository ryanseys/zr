# Binop is not a `fn` signature here
module Zr::Kern
  #: (word, word) -> word
  def add(a, b)
    a + b
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    Binop.call(Machine.addr(:add), 1, 2)
    0
  end
end
