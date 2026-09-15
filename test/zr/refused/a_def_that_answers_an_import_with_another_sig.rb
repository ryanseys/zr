# exit answers an import of [I32] => Void, and its sig differs
Machine.import "exit", [I32] => Void

sig [Word] => Void
machine def exit(code)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  0
end
