# binop is not a Machine.sig here
sig [Word, Word] => Word
machine def add(a, b)
  a + b
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  Machine.call(:binop, Machine.addr(:add), 1, 2)
  0
end
