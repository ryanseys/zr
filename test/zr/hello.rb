# The first light of the kernel dialect: write and exit through libSystem.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

sig [I32, Ptr] => I32
machine def main(argc, argv)
  msg = Machine.bytes("hello, zr!\n")
  n = 0
  while n < 3
    write(1, msg, 11)
    n += 1
  end
  exit(0)
  0
end
