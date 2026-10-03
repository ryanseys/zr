# a condition that is a Word; CRuby takes 0 as true, so compare it (`x != 0`)
module Zr::Kern
  #: (word) -> bool
  def zero_p(n)
    !n
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
