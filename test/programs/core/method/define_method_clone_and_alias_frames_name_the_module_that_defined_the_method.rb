# ruby 4.1 labels a frame with the module that defined the method
# (location_original_module, #22197), through define_method of an
# UnboundMethod, a clone or a dup, an alias in a subclass or a singleton
# class, and a refinement's alias. A module's method on its own singleton
# class, as module_function makes it, shows 'Mod.m'.
def labels
  yield
rescue StandardError => e
  p e.backtrace_locations.first(2).map(&:label)
end
module Orig; def m = raise("x"); end
class A; define_method(:m, Orig.instance_method(:m)); end
labels { A.new.m }
class P0; def pm = raise("p"); end
class P1 < P0; define_method(:pm2, P0.instance_method(:pm)); end
labels { P1.new.pm2 }
o = Object.new
o.singleton_class.define_method(:om, Orig.instance_method(:m))
labels { o.om }
Orig.singleton_class.define_method(:sm, Orig.instance_method(:m))
labels { Orig.sm }
class K; def k = raise("k"); def self.s = raise("s"); end
K2 = K.clone
labels { K2.new.k }
labels { K2.s }
K3 = K.dup
labels { K3.new.k }
M2 = Orig.dup
class UsesM2; include M2; end
labels { UsesM2.new.m }
class K; class << self; alias s2 s; end; end
labels { K.s2 }
class Sub < K; class << self; alias s3 s; end; end
labels { Sub.s3 }
x = Object.new
def x.foo = raise("f")
x.singleton_class.alias_method :bar, :foo
labels { x.bar }
y = x.clone
labels { y.foo }
mf = Module.new { module_function; def q = raise("q") }
labels { mf.q }
module Named; module_function; def q = raise("q"); end
labels { Named.q }
module Named2; def q = raise("q"); module_function :q; end
labels { Named2.q }
class Sub4 < K; alias_method :kk, :k; end
labels { Sub4.new.kk }
class Ref; def r = raise("r"); end
module RR; refine Ref do; alias_method :r2, :r; end; end
using RR
labels { Ref.new.r2 }
labels { [1].method(:fetch).unbind.bind_call([], 5) }
class AA < Array; define_method(:ff, Array.instance_method(:fetch)); end
labels { AA.new.ff(3) }
