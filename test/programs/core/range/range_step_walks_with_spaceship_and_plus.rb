# Range#step over values that are not numbers walks with <=> and + alone,
# in range_step's order, and yields nothing when the step goes the wrong
# way; a step that is not a number coerces in the first addition.
$stderr = $stdout
$log = []
class V
  def initialize(n) = @n = n
  attr_reader :n
  def <=>(o) = ($log << [:cmp, @n, o.n]; @n <=> o.n)
  def +(s) = ($log << [:plus, @n]; V.new(@n + s.n))
  def inspect = "V#{@n}"
end
rec = []
(V.new(1)..V.new(3)).step(V.new(1)) { rec << _1 }
p rec, $log
$log = []; rec = []
(V.new(3)..V.new(1)).step(V.new(-1)) { rec << _1 }
p rec, $log
$log = []; rec = []
(V.new(1)..V.new(3)).step(V.new(-1)) { rec << _1 }
p rec, $log
o = Object.new
def o.coerce(x) = [1, 2]
r = []
(1..3).step(o) { r << _1 }
p r
r = []; ("a".."aaaa").step("a") { r << _1 }; p r
r = []; ("a"..."aaaa").step("a") { r << _1 }; p r
r = []; (Time.at(0).utc..Time.at(10).utc).step(5) { r << _1.to_i }; p r
r = []; (1..10).step(3) { r << _1 }; p r
r = []; (10..1).step(-3) { r << _1 }; p r
r = []; (1.0..2.0).step(0.5) { r << _1 }; p r
r = []; (1r..2r).step(1/2r) { r << _1 }; p r
r = []; (2r..1r).step(-1/2r) { r << _1 }; p r
