# ruby 4.1's Module#descendants (Feature #9779): the classes and modules
# that have the receiver among their ancestors, walked down its subclass
# lists: subclasses in the order they were made, includers in the order
# of the includes, each before what is below it. No singleton class.
module M; end
module N; include M; end
class A; end
class B < A; include M; end
class C < B; end
class D < A; end
class E; include N; end
class F; end
F.include(M)
class G < E; end
o = Object.new
o.extend(M)
anon = Class.new(D)
module P; end
class D; prepend P; end
p A.descendants.map { |k| k.name || :anon }
p M.descendants
p N.descendants, P.descendants.map { |k| k.name || :anon }, B.descendants, C.descendants
p BasicObject.descendants.include?(G), Object.descendants.include?(M), Kernel.descendants.include?(A)
p Comparable.descendants.include?(Integer), Comparable.descendants.include?(Comparable)
p M.descendants.none?(&:singleton_class?), A.descendants.frozen?
p Module.instance_method(:descendants).arity, (A.descendants(1) rescue $!.message)
class LateIncluder; end
module Late; end
class Early < LateIncluder; end
Early.include(Late)
LateIncluder.include(Late)
p Late.descendants
module Base; end
module Mid; end
class UsesMid; include Mid; end
Mid.include(Base)
class UsesMid2; include Mid; end
p Base.descendants, Mid.descendants
module Pre; end
module Host; end
Host.prepend(Pre)
class UsesHost; include Host; end
p Pre.descendants, Host.descendants
k = Class.new
k2 = Class.new(k)
k3 = Class.new(k2)
p k.descendants == [k2, k3], k3.descendants
module Twice; end
class T1; include Twice; end
class T2 < T1; include Twice; end
p Twice.descendants
