# Binop is not a `fn` signature here
module Zr::Kern
  sig [Word, Word] => Word
  def add(a, b)
    a + b
  end

  sig [I32, Ptr] => I32
  def main(argc, argv)
    Binop.call(Machine.addr(:add), 1, 2)
    0
  end
end
