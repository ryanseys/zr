# basic is a RBasic; set its fields instead
module Zr::Kern
  RBasic = layout flags: Word, klass: Value
  RString = layout basic: RBasic, len: Word

  #: (i32, ptr) -> i32
  def main(argc, argv)
    p = Machine.slot(RString.size)
    RString.set_basic(p, 0)
    0
  end
end
