# + on a Value; Machine.word gives its bits
module Zr::Kern
  # A Value is a tagged word: only a comparison reads it as it is.
  #: (value, value) -> value
  def both(a, b)
    a + b
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
