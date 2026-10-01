# an import names its wasm module with `from: "module"`
module Zr::Kern
  Libc.import :fd_close, [I32] => I32, from: :wasi

  sig [I32, Ptr] => I32
  def main(argc, argv)
    0
  end
end
