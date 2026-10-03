# take wants a Ptr here, not a RBasic
module Zr::Kern
  class RBasic < Layout
    attr_accessor :flags #: word
  end

  class Box < Layout
    attr_reader :basic #: RBasic
    attr_accessor :len #: word
  end

  #: (ptr) -> word
  def take(p)
    0
  end

  # The address of a view is `Machine.ptr(view)`.
  #: (ptr) -> word
  def pass(p)
    take(Box[p].basic)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
