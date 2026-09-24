# One file of a three-file unit: main calls defs of both other files and
# names their import and constant.
sig [Word] => Word
machine def twice(n)
  n * 2
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  put_word(twice(BASE))
  put_word(later(3))
  exit(0)
  0
end
