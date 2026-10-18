# A &b parameter that the method only calls (b.call, b[], b.yield, b === x)
# runs the block it was given and makes no Proc, as CRuby's VM calls a
# block handler; a redefinition of one of those methods is called.
c = {}
GC.disable
def cl1(&b) = b.call(1)
def yld(&b) = b.yield(1)
def aref(&b) = b[1]
def eqq(&b) = b === 1
def ret(&b) = b
def measure(c)
  ObjectSpace.count_objects(c); n = c.dup
  yield
  ObjectSpace.count_objects(c); c.filter_map { |k, v| [k, v - n[k]] if k != :FREE && k != :TOTAL && v != n[k] }.to_h
end
def run(c)
  cl1 { }; yld { }; aref { }; eqq { }; ret { }
  a = measure(c) { }
  ObjectSpace.count_objects(c); n = c[:T_DATA]
  cl1 { }
  ObjectSpace.count_objects(c); r1 = c[:T_DATA] - n
  yld { }
  ObjectSpace.count_objects(c); r2 = c[:T_DATA] - n - r1
  aref { }
  ObjectSpace.count_objects(c); r3 = c[:T_DATA] - n - r1 - r2
  eqq { }
  ObjectSpace.count_objects(c); r4 = c[:T_DATA] - n - r1 - r2 - r3
  ret { }
  ObjectSpace.count_objects(c); r5 = c[:T_DATA] - n - r1 - r2 - r3 - r4
  [r1, r2, r3, r4, r5]
end
p run(c)
p Proc.instance_method(:===).original_name, proc { |x| x * 2 } === 3
def calls(&b) = [b.call(1), b[2], b.yield(3), b === 4, b.(5)]
p calls { |x| x * 10 }
class Proc
  def ===(x) = :redefined
end
p calls { |x| x }
