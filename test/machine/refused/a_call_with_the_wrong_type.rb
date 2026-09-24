# exit wants a I32 here, not a Word
Machine.import "exit", [I32] => Void

sig [I32, Ptr] => I32
machine def main(argc, argv)
  code = 3
  exit(code)
  0
end
