# a condition that is a Void
Machine.import "exit", [I32] => Void

sig [I32, Ptr] => I32
machine def main(argc, argv)
  if exit(0) && true
    1
  end
  0
end
