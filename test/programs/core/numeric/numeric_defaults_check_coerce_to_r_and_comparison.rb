# Numeric's defaults check what a subclass gives them: unary minus
# needs a pair from coerce, quo needs to_r, and remainder compares its
# operands with zero through `<` and `>`, which they must have.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue => e
  puts "#{name}: #{e.class}: #{e.message.sub(/0x\h+/, "0xADDR")}"
end

no_pair = Class.new(Numeric) { def coerce(_) = nil }.new
t("minus without a pair") { -no_pair }
t("compare without a pair") { 1 <=> no_pair }
pair = Class.new(Numeric) { def coerce(x) = [x, 1] }.new
t("minus with a pair") { -pair }
t("quo without to_r") { Numeric.new.quo(1) }
rat = 84.quo(1)
t("quo with to_r") { Class.new(Numeric) { define_method(:to_r) { rat } }.new.quo(42) }
odd = Class.new do
  def coerce(a) = [self, a]
  def %(_) = self
end.new
t("remainder without <") { 1.remainder(odd) }
t("remainder of integers") { [7.remainder(-3), -7.remainder(3), 4.remainder(Float::INFINITY)] }
