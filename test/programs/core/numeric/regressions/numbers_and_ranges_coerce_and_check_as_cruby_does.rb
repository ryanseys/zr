# Integer, Float, Rational and Range: coercion, conversions and edge
# cases as CRuby gives them (each line names its case by number).
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
big = 2**70
w = Object.new; def w.==(o) = "woot"
show(1) { big === w }
show(2) { big == w }
show(3) { 5 == w }
c = Object.new; def c.coerce(o) = :nope
show(4) { big <=> c }
d = Object.new; def d.coerce(o) = [o.to_f.then { |f| D.new(f) }, D.new(2.0)]
class D; def initialize(f) = @f = f; def div(o) = :divved; def /(o) = :slashed; end
show(5) { 6.div(d) }
show(6) { big.div(d) }
p2 = Object.new
class << p2; private def coerce(o) = [o, 2]; end
show(7) { 6 + p2 }
show(8) { 6 - p2 }
show(9) { 6 / p2 }
show(10) { 1.upto("a").size }
show(11) { 1.downto("a").size }
t = Object.new; def t.to_int = "x"
show(12) { big << t }
show(13) { big >> t }
show(14) { 2.pow(5, "x") }
inf = Object.new; def inf.infinite? = 1
show(15) { Float::INFINITY <=> inf }
ninf = Object.new; def ninf.infinite? = -1
show(16) { Float::INFINITY <=> ninf }
fin = Object.new; def fin.infinite? = nil
show(17) { Float::INFINITY <=> fin }
show(18) { Rational(0, 1)**Rational(-1, 2) }
b = BasicObject.new
show(19) { Rational(b) }
show(20) { Rational(1).quo(Object.new.tap { |o| def o.to_r = 0 }) }
class N < Numeric; def %(o) = :mod; def <(o) = false; def >(o) = false; def ==(o) = false; def zero? = false; end
show(21) { N.new.remainder(3) }
show(22) { (1..2).bsearch }
show(23) { ("a".."b").bsearch }
show(24) { (1..3).last(nil) }
show(25) { (1..nil).reverse_each.size }
show(26) { ("ঙ".."香").include?("馕") }
show(27) { 1.chr }
Encoding.default_internal = Encoding::UTF_8
show(28) { 300.chr }
Encoding.default_internal = nil
show(29) { 0.0 <=> inf }
o2 = Object.new
def o2.>(x) = (puts "> #{x}"; nil)
def o2.<(x) = (puts "< #{x}"; nil)
show(30) { (1..3).max { |a, b| o2 } }
class Step
  attr_reader :v
  def initialize(v) = @v = v
  def succ = Step.new(@v + 2)
  def <=>(o) = @v <=> o.v
  def ==(o) = o.is_a?(Step) && @v == o.v
end
show(31) { (Step.new(1)..Step.new(5)).include?(Step.new(2)) }
show(32) { (Step.new(1)..Step.new(5)).include?(Step.new(3)) }
class Sub < Numeric
  def to_r = 1
end
show(33) { Sub.new.quo(19) }
