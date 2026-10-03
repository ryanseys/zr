# exit wants a I32 here, not a Word
module Zr::Kern
  module Libc
    #: (i32) -> void
    def self.exit(status) = Machine.import
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    code = 3
    Libc.exit(code)
    0
  end
end
