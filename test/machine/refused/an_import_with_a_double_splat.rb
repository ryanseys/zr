# an import names its wasm module with `from: "module"`
module Zr::Kern
  module Libc
    #: (i32) -> i32
    def self.fd_close(fd) = Machine.import(**WASI)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
