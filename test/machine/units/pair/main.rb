# One file of a three-file unit: main calls defs of both other files and
# names their import and constant.
module Zr::Kern
  #: (word) -> word
  def twice(n)
    n * 2
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    put_word(twice(BASE))
    put_word(later(3))
    Libc.exit(0)
    0
  end
end
