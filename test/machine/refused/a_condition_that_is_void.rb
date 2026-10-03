# a condition that is a Void
module Zr::Kern
  module Libc
    #: (i32) -> void
    def self.exit(status) = Machine.import
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    if Libc.exit(0) && true
      1
    end
    0
  end
end
