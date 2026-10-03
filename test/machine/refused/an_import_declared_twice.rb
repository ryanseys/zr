# getpid is already imported
module Zr::Kern
  module Libc
    #: () -> i32
    def self.getpid = Machine.import
  end

  # Each import has one home: a second module Libc of another file can
  # give it another type.
  module Libc
    #: () -> word
    def self.getpid = Machine.import
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    Libc.getpid()
  end
end
