# `is_a?`, `kind_of?` and `instance_of?` are Kernel's for every
# object, so a site answers them from the classes alone with no
# cell (GATE_IS_A, GATE_INSTANCE_OF); a definition of the name --
# by def, alias, define_method or a singleton -- closes the gate for
# every site, and a BasicObject has no is_a? to answer. `Mod ===
# obj` answers from the classes where the arm's cell holds
# Module's === (SHAPE_MOD_EQQ), and calls whatever else it holds --
# a `===` on a singleton, on Module, on Object.
class Num; end
class Sub < Num; end
module Mod; end
class WithMod; include Mod; end
n = Num.new; s = Sub.new; w = WithMod.new
p n.is_a?(Num), s.is_a?(Num), n.is_a?(Sub), s.kind_of?(Object), n.is_a?(Mod), w.is_a?(Mod), w.kind_of?(Comparable)
p n.instance_of?(Num), s.instance_of?(Num), s.instance_of?(Sub), w.instance_of?(Mod)
p nil.is_a?(NilClass), true.is_a?(TrueClass), 1.is_a?(Integer), 1.is_a?(Comparable), :s.is_a?(Symbol), 2.5.is_a?(Float), 1.instance_of?(Integer)
begin
  n.is_a?(3)
rescue TypeError => e
  puts e.message
end
begin
  BasicObject.new.is_a?(Object)
rescue NoMethodError => e
  puts e.message
end
class Bare < BasicObject
  def is_a?(k) = :bare
end
p Bare.new.is_a?(Object)
def probe(x) = x.is_a?(Num)
p probe(n), probe(s), probe(1)
class Sub
  def is_a?(k) = :redefined
end
p probe(s), probe(n), s.kind_of?(Num), n.kind_of?(Num)
class Num
  alias kind_of? is_a?
end
p n.kind_of?(Num)
o = Object.new
def o.instance_of?(k) = :single
p o.instance_of?(Object), Object.new.instance_of?(Object)
class Late; end
l = Late.new
def late_probe(x) = x.instance_of?(Late)
p late_probe(l)
Late.define_method(:instance_of?) { |k| :defined }
p late_probe(l)
# `case` arms ask Module#===
def classify(x)
  case x
  when Num then :num
  when Sub then :sub
  when Mod then :mod
  when Integer then :int
  when NilClass then :nil
  else :other
  end
end
p classify(n), classify(s), classify(w), classify(1), classify(nil), classify("s")
class Late2; end
def late_case(x) = (case x when Late2 then :late else :no end)
p late_case(Late2.new), late_case(1)
def Late2.===(o) = :singleton
p late_case(Late2.new), late_case(1), classify(n)
class Module
  def ===(o) = :module_eqq
end
p classify(n), classify(1)
