# Machine.popcnt of an I32 counts 64 bits on CRuby; widen it first (Machine.u32)
module Zr::Kern
  #: (i32, ptr) -> i32
  def main(argc, argv)
    Machine.i32(Machine.popcnt(argc))
  end
end
