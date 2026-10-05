# super raises TypeError when an instance_eval in the method made self
# an object that is not a kind of the method's class; the message names
# a module's method by the class that includes it.
class Sup; def foo = [:sup, self.class]; end
module Mod; def foo; Object.new.instance_eval { super() }; end; end
class Sub < Sup; def foo; Object.new.instance_eval { super() }; end; end
class Sub2 < Sup; include Mod; end
class Sub2b < Sub2; end
class Sub3 < Sup; define_method(:foo) { Object.new.instance_eval { super() } }; end
class Sub4 < Sup; def foo; 5.instance_eval { super() }; end; end
class Sub5 < Sup; def foo; lam = Object.new.instance_eval { -> { super() } }; lam.call; end; end
class Fine < Sup; def foo; Fine.new.instance_eval { super() }; end; end
module Bound; def foo = [:bound, super]; end
[Sub, Sub2, Sub2b, Sub3, Sub4, Sub5, Fine].each do |k|
  p k.new.foo
rescue TypeError => e
  p [e.class, e.message]
end
p Bound.instance_method(:foo).bind_call(Sup.new)
