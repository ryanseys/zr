# a machine def takes required parameters only
module Zr::Kern
  #: (word, word) -> word
  def add((a, b), c)
    c
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
