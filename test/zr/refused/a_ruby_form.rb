# Array is not in the kernel dialect
sig [I32, Ptr] => I32
machine def main(argc, argv)
  xs = [1, 2]
  0
end
