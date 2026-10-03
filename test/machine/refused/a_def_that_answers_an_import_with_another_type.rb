# exit answers an import of (i32) -> void, and its type differs
module Zr::Kern
  module Libc
    #: (i32) -> void
    def self.exit(status) = Machine.import
  end

  #: (word) -> void
  def exit(code)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
