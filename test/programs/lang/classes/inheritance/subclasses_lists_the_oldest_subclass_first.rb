# ruby 4.1 keeps a class's subclasses in an array in creation order
# (f71840a230), so Class#subclasses gives the oldest first. A clone or a
# dup of a subclass is a subclass too, and a singleton class is never one.
class A; end
class B < A; end
B2 = B.clone
class C < A; end
d = B.dup
anon = Class.new(A)
p A.subclasses.size, A.subclasses[0, 3], A.subclasses[3].equal?(d), A.subclasses[4].equal?(anon)
p B.subclasses, C.subclasses
a = A.new
def a.x = 1
p A.subclasses.size, A.subclasses.none?(&:singleton_class?)

# Classes made in a loop, and a nested hierarchy.
k = Class.new
made = Array.new(5) { |i| Class.new(k).tap { |c| c.define_method(:i) { i } } }
p k.subclasses == made, k.subclasses.map { |c| c.new.i }
mid = Class.new(made[2])
leaf = Class.new(mid)
p made[2].subclasses == [mid], mid.subclasses == [leaf], k.subclasses.size

# Struct and Data classes.
S = Struct.new(:x)
T = Struct.new(:y)
p Struct.subclasses.last(2) == [S, T]
P = Data.define(:a)
Q = Data.define(:b)
p Data.subclasses.last(2) == [P, Q]
