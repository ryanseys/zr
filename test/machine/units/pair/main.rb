# One file of a three-file unit: main calls defs of both other files and
# names their import and constant.
module Zr::Kern
  sig [Word] => Word
  def twice(n)
    n * 2
  end

  sig [I32, Ptr] => I32
  def main(argc, argv)
    put_word(twice(BASE))
    put_word(later(3))
    Libc.exit(0)
    0
  end
end
