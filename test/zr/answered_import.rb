# A def of an imported name answers that import's calls: `exit` here
# says goodbye before it leaves through `_exit`.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void
Machine.import "_exit", [I32] => Void

sig [I32] => Void
machine def exit(code)
  write(1, Machine.bytes("bye\n"), 4)
  _exit(code)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  write(1, Machine.bytes("hi\n"), 3)
  exit(0)
  0
end
