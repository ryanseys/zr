# A dup of a module with a prepended module has its own origin, so the
# copy's ancestors are the prepended module and the copy.
m1 = Module.new { def calc(x) = [:m1, x] }
m2 = Module.new do
  prepend(m1)
  def calc(x) = [:m2, super]
end
c1 = Class.new { prepend(m2) }
m2dup = m2.dup
show = ->(list, names) { list.map { |m| names.fetch(m, m) } }
names = { m1 => :m1, m2 => :m2, m2dup => :m2dup, c1 => :c1 }
p show.(m2dup.ancestors, names)
c2 = Class.new { prepend(m2dup) }
names[c2] = :c2
p show.(c2.ancestors.take(4), names)
p show.(c1.ancestors.take(4), names)
p c1.new.kind_of?(m1), c2.new.kind_of?(m1)
p c2.new.calc(1), c1.new.calc(2)
m2dup.define_method(:extra) { 1 }
p m2.method_defined?(:extra), m2dup.method_defined?(:extra)

module A
  def hi = [:a, super]
end

module B
  prepend A
  def hi = [:b, super]
end

class K
  def hi = :k
end

class C < K
  include B
  prepend A
  def hi = [:c, super]
end
D = C.dup
p D.ancestors.take(6).map { |m| m.name || :anon }
p D.new.hi, C.new.hi
p D.instance_method(:hi).owner == D
