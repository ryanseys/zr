# a condition that is a Word; CRuby takes 0 as true, so compare it (`x != 0`)
module Zr::Kern
  #: (i32, ptr) -> i32
  def main(argc, argv)
    n = 0
    if n
      return 1
    end
    0
  end
end
