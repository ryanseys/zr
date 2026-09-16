# `is_a?` with a class argument answers from the receiver's list of
# superclasses; an uninitialized class (Class.allocate) has an open chain,
# which `Class.new` refuses to inherit and the `class` keyword accepts,
# and it answers by a walk; a subclass under it never gets an allocator.
class A; end
class B < A; end
class C < B; end
module M; end
class D < C; include M; end

c = C.new
d = D.new
p [c.is_a?(A), c.is_a?(B), c.is_a?(C), c.is_a?(D), c.is_a?(M), c.is_a?(Object), c.is_a?(BasicObject)]
p [d.is_a?(A), d.is_a?(C), d.is_a?(D), d.is_a?(M), d.is_a?(Comparable), d.kind_of?(Kernel)]
p [A === c, C === c, D === c, M === d, Class === c, Module === C, Class === C]
s = c.singleton_class
p [c.is_a?(s), C.new.is_a?(s), s.is_a?(Class), C.is_a?(Class), C.is_a?(Module), C.is_a?(A)]

open = Class.allocate
begin
  Class.new(open)
rescue TypeError => e
  p [e.class, e.message]
end
Open = open
class Under < Open; end
begin
  Under.allocate
rescue TypeError => e
  p [e.class, e.message]
end
p [Under.ancestors, Under.is_a?(Class), C.new.is_a?(Under)]
def open.tag = :before
open.send(:initialize, A)
p [Under.ancestors.take(4), Open.superclass, C.new.is_a?(Under), A.new.is_a?(Open), open.new.is_a?(A), open.new.is_a?(Under)]
p [(open.tag rescue :gone), open.singleton_class.instance_methods(false)]
begin
  Under.new
rescue TypeError => e
  p [e.class, e.message]
end
begin
  open.send(:initialize, A)
rescue TypeError => e
  p [e.class, e.message]
end

begin
  c.is_a?(3)
rescue TypeError => e
  p [e.class, e.message]
end
p [1.is_a?(Integer), 1.is_a?(Comparable), nil.is_a?(NilClass), :s.is_a?(Symbol), 1.5.is_a?(Float), 1.instance_of?(Integer), 1.instance_of?(Numeric)]
case c
when D then p :d
when B then p :b
end
begin
  raise IOError, "x"
rescue StandardError => e
  p [e.is_a?(IOError), e.is_a?(StandardError), e.class.ancestors.index(StandardError)]
end


__END__
[true, true, true, false, false, true, true]
[true, true, true, true, false, true]
[true, true, false, true, false, true, true]
[true, false, true, true, true, false]
[TypeError, "can't inherit uninitialized class"]
[TypeError, "allocator undefined for Under"]
[[Under, Open], true, false]
[[Under, Open, A, Object], A, false, false, true, false]
[:gone, []]
[TypeError, "allocator undefined for Under"]
[TypeError, "already initialized class"]
[TypeError, "class or module required"]
[true, true, true, true, true, true, false]
:b
[true, true, 1]
