# basic is a RBasic; set its fields instead
Machine.struct :RBasic, flags: Word, klass: Value
Machine.struct :RString, basic: RBasic, len: Word

sig [I32, Ptr] => I32
machine def main(argc, argv)
  p = Machine.slot(RString.size)
  RString.set_basic(p, 0)
  0
end
