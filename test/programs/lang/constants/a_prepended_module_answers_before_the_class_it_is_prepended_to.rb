# A constant lookup that reaches a class with a prepended module reads
# the module first; the class itself answers first only when the lookup
# starts there (Bug #17887).
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message[0, 70]]
end
m = Module.new { const_set(:C, :m) }
c = Class.new { const_set(:C, :c); prepend m }
sc = Class.new(c)
t(:const) { [sc.const_get(:C), sc::C, c::C, c.const_get(:C)] }
pm2 = Module.new { const_set(:D, :pm2) }
mod = Module.new { const_set(:D, :mod); prepend pm2 }
host = Class.new { include mod }
t(:module_prepend) { [host.const_get(:D), mod::D, Class.new(host)::D] }
outer = Class.new { const_set(:F, :outer) }
inner = Class.new(outer) { prepend Module.new }
t(:inherited) { [inner::F, inner.const_get(:F)] }
