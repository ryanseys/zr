# A constant read answers from its site's cell while the cref and the
# constant stamp hold: a constant set, removed or reopened
# after the first read is seen by the same site, and a site inside a
# block or a define_method body reads under its own cref.
A = 1
def read_a = A
p read_a, read_a
Object.send(:remove_const, :A)
A = 2
p read_a
module M
  X = :m
  def self.read = X
  Y = :y
end
p M.read, M::X, M::Y
M.send(:remove_const, :X)
M.const_set(:X, :again)
p M.read, M::X
class Base
  C = :base
  def c = C
end
class Kid < Base
  def kc = C
end
p Kid.new.c, Kid.new.kc
class Kid
  C = :kid
end
p Kid.new.c, Kid.new.kc
reader = proc { A }
p reader.call
Object.send(:remove_const, :A)
A = 3
p reader.call, read_a
Object.const_set(:Later, 4)
p (Later), Object.const_defined?(:Later)
klass = Class.new do
  Z = :z
  define_method(:z) { Z }
end
p klass.new.z, Z
i = 0
total = 0
while i < 100_000
  total += A
  i += 1
end
p total
p (Missing rescue $!.class)


