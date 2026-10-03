# + on a view; Machine.ptr takes its address
module Zr::Kern
  class RBasic < Layout
    attr_accessor :flags #: word
  end

  class Box < Layout
    attr_reader :basic #: RBasic
    attr_accessor :len #: word
  end

  # A view is not a number: on CRuby it is an object.
  #: (ptr) -> ptr
  def after(p)
    Box[p].basic + 8
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    0
  end
end
