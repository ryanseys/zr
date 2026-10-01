# RBasic has no field klas
module Zr::Kern
  RBasic = layout flags: Word, klass: Value

  sig [I32, Ptr] => I32
  def main(argc, argv)
    p = Machine.slot(16)
    RBasic.set_klas(p, Machine.value(0))
    0
  end
end
