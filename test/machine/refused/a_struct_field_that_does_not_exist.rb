# RBasic has no field klas
module Zr::Kern
  class RBasic < Layout
    attr_accessor :flags #: word
    attr_accessor :klass #: value
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    p = Machine.slot(16)
    RBasic[p].klas = Machine.value(0)
    0
  end
end
