# an import names its wasm module with `from: "module"`
Machine.import "fd_close", [I32] => I32, from: :wasi

sig [I32, Ptr] => I32
machine def main(argc, argv)
  0
end
