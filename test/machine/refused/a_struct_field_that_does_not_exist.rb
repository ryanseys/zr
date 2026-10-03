# RBasic has no field klas
module Zr::Kern
  RBasic = layout flags: Word, klass: Value

  #: (i32, ptr) -> i32
  def main(argc, argv)
    p = Machine.slot(16)
    RBasic.set_klas(p, Machine.value(0))
    0
  end
end
