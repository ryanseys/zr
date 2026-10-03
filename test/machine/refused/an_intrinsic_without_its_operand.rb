# Machine.u32 takes one operand
module Zr::Kern
  #: (i32, ptr) -> i32
  def main(argc, argv)
    Machine.u32()
    0
  end
end
