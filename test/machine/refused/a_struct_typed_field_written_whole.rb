# basic is a RBasic; set its fields instead
module Zr::Kern
  class RBasic < Layout
    attr_accessor :flags #: word
    attr_accessor :klass #: value
  end

  class RString < Layout
    attr_reader :basic #: RBasic
    attr_accessor :len #: word
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    p = Machine.slot(RString.size)
    RString[p].basic = 0
    0
  end
end
