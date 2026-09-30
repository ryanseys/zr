# A ranked class -- one in Object's family with its rank table built,
# which every class gets at birth -- answers `is_a?`, a `case` arm and
# `nil?` at the site from its header and its table, with no call
# (FL_RANKED, GATE_NIL_P); `==`, `equal?` and `!=` answer by identity
# where the cell holds BasicObject's (SHAPE_EQ, SHAPE_NE). A module, a
# BasicObject's class, a class made by Class.allocate, and every
# definition of one of the names take the road that calls.
class A; end
class B < A; end
class C < B; end
module M; end
class D; include M; end
class Bare < BasicObject; def self.mk = new; end
a, b, c, d = A.new, B.new, C.new, D.new
p [a.nil?, nil.nil?, 1.nil?, :s.nil?, 1.5.nil?, "".nil?, true.nil?, (Bare.mk.nil? rescue $!.class)]
p [b.is_a?(A), a.is_a?(B), c.kind_of?(A), c.is_a?(Object), c.is_a?(BasicObject), c.is_a?(Kernel), d.is_a?(M), a.is_a?(M), 1.is_a?(Integer), 1.is_a?(Comparable), nil.is_a?(NilClass), 1.5.is_a?(Float), 1.is_a?(Float)]
p [(a.is_a?(1) rescue $!.class), (a.is_a?(nil) rescue $!.class), A.is_a?(Class), A.is_a?(A), a.is_a?(a.singleton_class), (Bare.mk.is_a?(Object) rescue $!.class)]
def kind(x)
  case x
  when C then :c
  when B then :b
  when A then :a
  when M then :m
  when Integer then :int
  when Symbol then :sym
  when NilClass then :nil
  when Comparable then :cmp
  when BasicObject then :basic
  else :other
  end
end
p [a, b, c, d, 1, 1.5, :s, nil, Bare.mk, 2**70].map { |x| kind(x) }
p [A === a, B === a, M === d, M === a, Class === A, Module === M, BasicObject === Bare.mk, Object === Bare.mk]
p [a == a, a == b, a != a, a != b, a.equal?(a), a.equal?(b), nil != false, :s == :s, :s != :t, A == A, A != B, "a" == "a", "a" != "b", 1 == 1.0, 1 != 1.0]
class E; def ==(o) = true; end
class F; def !=(o) = :ne; end
class G < A; def nil? = :g; end
class H; def is_a?(k) = :h; end
class I; def self.===(o) = :i; end
p [E.new == E.new, E.new != E.new, E.new.equal?(E.new), F.new != F.new, F.new == F.new, G.new.nil?, a.nil?, nil.nil?, H.new.is_a?(A), a.is_a?(A), (case 1 when I then :yes else :no end), kind(c)]
s = Class.new(A)
t = Class.new(s)
k = Class.allocate
u = Class.new
p [t.new.is_a?(A), s === t.new, B === t.new, (k.new rescue $!.class), u.new.is_a?(Object), u === u.new, u.new.nil?]
n = 0
i = 0
while i < 100_000
  n += 1 if kind(i.even? ? b : c) == :b
  n += 1 if b.nil?
  n += 1 if b != c
  n += 1 if c.is_a?(A)
  i += 1
end
p n
