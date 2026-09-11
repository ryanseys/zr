# native only
# Every send, constant read and ivar access below runs from one site
# more than once, so a site's cell answers the later runs; each change
# between runs must reach the next answer.
def show(label)
  answer = yield.inspect rescue "#{$!.class}: #{$!.message}"
  puts("#{label}: #{answer.gsub(/0x\h+/, "0xXX")}")
end

# One send site, many receiver classes, and definitions in between.
class A; def who = "A"; end
class B; def who = "B"; end
class C < A; end
def ask(o) = o.who
show("polymorphic") { [A.new, B.new, C.new, A.new, 1.then { B.new }].map { ask(_1) } }
class A; def who = "A2"; end
show("redefined") { [A.new, C.new].map { ask(_1) } }
module Loud; def who = "loud #{super}"; end
C.include(Loud)
show("included") { [A.new, C.new].map { ask(_1) } }
C.prepend(Module.new { def who = "pre #{super}" })
show("prepended") { ask(C.new) }
o = A.new
show("before singleton") { ask(o) }
def o.who = "single"
show("singleton") { [ask(o), ask(A.new)] }
class B; private :who; end
show("made private") { ask(B.new) }
class B; public :who; end
show("made public") { ask(B.new) }
class B; protected :who; end
show("made protected") { ask(B.new) }
class B; undef_method :who; end
show("undefined") { ask(B.new) }
class B; def method_missing(name, *) = "missing #{name}"; end
show("missing") { ask(B.new) }
class B; alias_method :who, :to_s; end
show("aliased") { ask(B.new).sub(/:0xXX|:0x\h+/, "") }
show("specials") { [1, :s, nil, 1.5, true].map { ask(_1) rescue $!.class } }
class Integer; def who = "int"; end
show("integer who") { [ask(1), ask(2**70)] }

# Arity through a cached site, and keywords.
class K
  def one(a) = a
  def kw(a:, b: 2) = [a, b]
end
def one_of(o, *args) = o.one(*args)
show("arity") { [one_of(K.new, 1), (one_of(K.new) rescue $!.message), one_of(K.new, 3)] }
def kw_of(o, **kw) = o.kw(**kw)
show("keywords") { [kw_of(K.new, a: 1), kw_of(K.new, a: 1, b: 3), (kw_of(K.new) rescue $!.message)] }

# Accessors read and write through the site's guess.
class Pt
  attr_accessor :x, :y
  def initialize(x, y) = (@x = x; @y = y)
end
class Rev
  attr_accessor :x, :y
  def initialize(x, y) = (@y = y; @x = x)
end
def getx(o) = o.x
def setx(o, v) = o.x = v
show("accessors") { [Pt.new(1, 2), Rev.new(3, 4), Pt.new(5, 6)].map { setx(_1, getx(_1) * 10); _1.x } }
f = Pt.new(1, 2).freeze
show("frozen writer") { setx(f, 9) }

# `new` through its two cells.
class N; def initialize(v) = @v = v; attr_reader :v; end
def make(k, v) = k.new(v)
show("new") { [make(N, 1).v, make(N, 2).v] }
class N; def initialize(v) = @v = v * 100; end
show("new, initialize redefined") { make(N, 3).v }
class N; def self.new(v) = "custom #{v}"; end
show("new, redefined new") { make(N, 4) }
show("new on Integer") { make(Integer, 1) }

# Instance variables: rows in different orders, removal, classes.
class Iv
  def initialize(first) = first ? (@a = 1; @b = 2) : (@b = 20; @a = 10)
  def a = @a
  def b = @b
  def set_a(v) = @a = v
  def drop_a = remove_instance_variable(:a.then { :@a })
end
show("ivar orders") { [Iv.new(true), Iv.new(false), Iv.new(true)].map { [_1.a, _1.b] } }
i = Iv.new(true)
show("ivar removed") { i.drop_a; [i.a, i.b, i.set_a(5), i.a, i.b, i.instance_variables] }
j = Iv.new(false).freeze
show("ivar frozen") { j.set_a(1) }
class Iv; @count = 1; def self.count = @count; def self.bump = @count += 1; end
show("class ivar") { [Iv.count, Iv.bump, Iv.bump, Iv.count] }
s = +"str"
s.instance_variable_set(:@a, "on a string")
show("ivar on a string") { Iv.instance_method(:a).bind(s).call rescue $!.class }
show("ivar on main") { @top = 1; @top += 1; @top }

# Constants: rebinding, removal, scopes, lexical against inherited.
X = 1
def x = X
show("constant") { [x, x] }
Object.send(:remove_const, :X)
show("removed") { x }
X = 2
show("set again") { x }
module Outer
  V = :outer
  class Inner
    def v = V
  end
end
class Base2; V = :base; end
class Outer::Inner2 < Base2
  def v = V
end
show("lexical") { [Outer::Inner.new.v, Outer::Inner2.new.v] }
Outer.send(:remove_const, :V)
show("lexical gone") { [(Outer::Inner.new.v rescue $!.class), Outer::Inner2.new.v] }
module Mixin; V = :mixin; end
Outer::Inner.include(Mixin)
show("from a mixin") { Outer::Inner.new.v }
def scoped = Outer::Inner
show("scoped") { [scoped, scoped] }
Outer.private_constant(:Inner)
show("made private") { scoped }
Outer.public_constant(:Inner)
Outer.deprecate_constant(:Inner)
Warning[:deprecated] = true
show("deprecated") { scoped }
Warning[:deprecated] = false
class Missing; def self.const_missing(n) = "missing #{n}"; end
class Missing; def m = Nope; def self.m = Nope; end
show("const_missing") { [Missing.m, Missing.m] }
Missing.const_set(:Nope, :now)
show("const_set") { [Missing.m, Missing.new.m] }
many = 3.times.map { |k| Class.new { const_set(:K, k); def k = self.class::K } }
show("one site, many classes") { many.map(&:new).map(&:k) }
show("evaluated classes") { 3.times.map { |k| Class.new(Base2) { define_method(:v2) { V } }.new.v2 } }
