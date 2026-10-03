# a declaration takes required parameters only
module Zr::Kern
  module Libc
    #: (i32) -> i32
    def self.fd_close(fd:) = Machine.import
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
