# Complex with other Numerics: a real one acts on the parts, any other
# coerces (with quo for a division); eql?, == and infinite?.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
class RealNum < Numeric
  def initialize(v) = @v = v
  def real? = true
  def coerce(o) = [o, @v]
  def ==(o) = @v == o
  def quo(o) = @v.quo(o)
end
class UnrealNum < Numeric
  def real? = false
  def coerce(o) = [Complex(5, 0), Complex(2, 0)]
end
c = Complex(3, 4)
show(1) { c.coerce(RealNum.new(2)).map(&:class) }
show(2) { (c + RealNum.new(2)) }
show(3) { c - RealNum.new(2) }
show(4) { c * RealNum.new(2) }
show(5) { Complex(5, 0) / UnrealNum.new }
show(6) { Complex(5, 0) + UnrealNum.new }
show(7) { Complex(2, 0) == RealNum.new(2) }
show(8) { Complex(1, 2).eql?(Complex(1, 2)) }
show(9) { Complex(1.0, 2).eql?(Complex(1, 2)) }
show(10) { Complex(Float::NAN, 1).infinite? }
show(11) { Complex(Float::INFINITY, 1).infinite? }
