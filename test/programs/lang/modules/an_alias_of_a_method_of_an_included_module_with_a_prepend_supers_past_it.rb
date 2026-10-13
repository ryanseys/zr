# A class's alias of a method from an included module that has a module
# prepended to it runs with super from that module's place: super goes on
# to the superclass, once (ruby #16736).
a = Class.new { def m = "A" }
m = Module.new do
  prepend Module.new
  def self.included(base) = base.alias_method(:base_m, :m)
  def m = super + "M"
  def m2 = base_m
end
b = Class.new(a) { include m }
p b.new.m2, b.new.m, b.new.base_m

# The prepended module's own method runs first through the alias too.
pre = Module.new { def n = "P(" + super + ")" }
n = Module.new do
  prepend pre
  def n = super + "N"
end
e = Class.new(Class.new { def n = "E" }) do
  include n
  alias_method :n2, :n
end
p e.new.n, e.new.n2

# Without a prepend the alias already supers from the module.
plain = Module.new { def k = super + "K" }
f = Class.new(Class.new { def k = "F" }) do
  include plain
  alias_method :k2, :k
end
p f.new.k2, f.instance_method(:k2).owner == plain
