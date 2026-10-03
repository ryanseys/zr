# a signature's parameters are an array of types
module Zr::Kern
  Libc.import :fd_close, **WASI

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
